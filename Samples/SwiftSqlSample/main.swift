import Foundation
import CosmoApiServer
import CosmoMSSQL

print("--- SwiftSqlSample Starting ---")

// Load .env file
Environment.loadDotEnv()

let builder = CosmoWebApplicationBuilder()
builder.configurationBuilder.addJsonFile("Samples/SwiftSqlSample/appsettings.json")

// 1. Try to get connection string from .env / process env first
// 2. Fallback to appsettings.json via Configuration
let connStr = Environment.get("MSSQL_CONN_STR") 
    ?? builder.configuration.getString("ConnectionStrings:MsSql") 
    ?? ""

print("Resolved Connection String: \(connStr.isEmpty ? "NONE" : "FOUND (HIDDEN)")")

// Load port from config, default to 8081
let port = builder.configuration.getInt("Server:Port") ?? 8081
builder.listenOn(port: port)

builder.useErrorHandling()
builder.useLogging()
builder.useStaticFiles(at: "Samples/SwiftSqlSample/wwwroot")

let app = builder.build()

// Initialize SQL Pool
if !connStr.isEmpty {
    var host = "127.0.0.1"
    var db = "master"
    var user = "sa"
    var pass = ""
    
    for part in connStr.components(separatedBy: ";") {
        let kv = part.components(separatedBy: "=")
        if kv.count == 2 {
            let key = kv[0].trimmingCharacters(in: .whitespaces).lowercased()
            let val = kv[1].trimmingCharacters(in: .whitespaces)
            switch key {
            case "server": host = val
            case "database": db = val
            case "user id": user = val
            case "password": pass = val
            default: break
            }
        }
    }
    
    print("Initializing MSSQL Pool for host: \(host), db: \(db)")
    let config = MSSQLConnection.Configuration(
        host: host,
        database: db,
        username: user,
        password: pass,
        trustServerCertificate: true
    )
    let pool = MSSQLConnectionPool(configuration: config, maxConnections: 10)
    QueryController.setPool(pool)
    print("SQL Pool successfully set on QueryController.")
} else {
    print("WARNING: No connection string found. Pool NOT initialized.")
}

// Global Layouts
app.appComponent = AppComponent()
app.mainLayout = MainLayout()

app.get("/") { ctx in
    try await ComponentResult(HomeComponent()).execute(response: ctx.response)
}

app.addController(QueryController.self)

print("SwiftSqlSample running on http://localhost:\(port)")
try await app.run()
