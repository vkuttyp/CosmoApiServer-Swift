import Foundation
import CosmoApiServer
import CosmoMSSQL
import CosmoSQLCore

public final class QueryController: ControllerBase, Controller, @unchecked Sendable {
    private static var _pool: MSSQLConnectionPool?
    
    public static func setPool(_ pool: MSSQLConnectionPool) {
        _pool = pool
    }

    public static func registerRoutes(on app: CosmoWebApplication) {
        app.get("/query") { ctx in
            try await ComponentResult(QueryComponent()).execute(response: ctx.response)
        }
        
        app.post("/query/run") { ctx in
            let form = try ctx.request.readMultipart()
            let sql = form.fields["sql"] ?? "SELECT * FROM sys.objects"
            
            var model = SqlQueryModel()
            model.sql = sql
            
            guard let pool = _pool else {
                model.error = "Database connection pool not initialized."
                var comp = QueryComponent()
                comp.model = model
                return try await ComponentResult(comp).execute(response: ctx.response)
            }
            
            let start = Date()
            do {
                let rows = try await pool.query(sql, [])
                
                if !rows.isEmpty {
                    // Extract column names from the first row
                    model.columns = rows[0].columns.map { $0.name }
                    
                    // Extract values
                    model.rows = rows.map { row in
                        row.columns.map { col -> String? in
                            let val = row[col.name]
                            if val == .null { return nil }
                            return "\(val.toAny() ?? "NULL")"
                        }
                    }
                }
            } catch {
                model.error = "\(error)"
            }
            model.elapsedSeconds = Date().timeIntervalSince(start)
            
            var comp = QueryComponent()
            comp.model = model
            return try await ComponentResult(comp).execute(response: ctx.response)
        }
    }
}
