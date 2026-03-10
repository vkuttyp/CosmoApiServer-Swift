import Foundation

public struct SwaggerUIMiddleware: Middleware {
    private let path: String
    private let openApiUrl: String

    public init(path: String = "/swagger", openApiUrl: String = "/openapi.json") {
        self.path = path
        self.openApiUrl = openApiUrl
    }

    public func invoke(_ context: HttpContext, next: RequestDelegate) async throws {
        if context.request.method == .get && context.request.path == path {
            context.response.setStatus(200)
            context.response.writeText(generateHtml(), contentType: "text/html; charset=utf-8")
            return
        }

        try await next(context)
    }

    private func generateHtml() -> String {
        return """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Swagger UI</title>
    <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
    <style>
        html { box-sizing: border-box; overflow: -moz-scrollbars-vertical; overflow-y: scroll; }
        *, *:before, *:after { box-sizing: inherit; }
        body { margin: 0; background: #fafafa; }
    </style>
</head>
<body>
    <div id="swagger-ui"></div>
    <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js" charset="UTF-8"></script>
    <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-standalone-preset.js" charset="UTF-8"></script>
    <script>
    window.onload = function() {
        const ui = SwaggerUIBundle({
            url: "\(openApiUrl)",
            dom_id: '#swagger-ui',
            deepLinking: true,
            presets: [
                SwaggerUIBundle.presets.apis,
                SwaggerUIStandalonePreset
            ],
            plugins: [
                SwaggerUIBundle.plugins.DownloadUrl
            ],
            layout: "StandaloneLayout"
        });
        window.ui = ui;
    };
    </script>
</body>
</html>
"""
    }
}
