import Foundation
import CosmoApiServer

public struct QueryComponent: Component {
    public var context: HttpContext?
    public var model: SqlQueryModel = SqlQueryModel()
    
    public init() {}
    
    public var body: HTMLContent {
        #html {
            Div {
                Div(attributes: ["class": "card mb-4"]) {
                    Div(attributes: ["class": "card-header bg-primary text-white"]) {
                        H1(attributes: ["class": "mb-0 h3"]) { "SQL Stream Viewer (SSR)" }
                    }
                    Div(attributes: ["class": "card-body"]) {
                        HTMLElement(tag: "form", attributes: [
                            "method": "post", 
                            "action": "/query/run",
                            "enctype": "multipart/form-data"
                        ]) {
                            Div(attributes: ["class": "mb-3"]) {
                                HTMLElement(tag: "textarea", attributes: [
                                    "name": "sql",
                                    "class": "form-control sql-editor",
                                    "placeholder": "SELECT * FROM sys.objects"
                                ]) { model.sql }
                            }
                            Div(attributes: ["class": "d-flex gap-2"]) {
                                HTMLElement(tag: "button", attributes: ["type": "submit", "class": "btn btn-success px-4"]) { "Run Query" }
                                HTMLElement(tag: "a", attributes: ["href": "/query", "class": "btn btn-outline-secondary"]) { "Reset" }
                            }
                        }
                    }
                }
                
                if let error = model.error {
                    Div(attributes: ["class": "alert alert-danger", "role": "alert"]) {
                        HTMLElement(tag: "strong") { "Error: " }
                        error
                    }
                }
                
                if !model.columns.isEmpty {
                    Div(attributes: ["class": "mb-2 text-muted small"]) {
                        HTMLElement(tag: "strong") { "\(model.rows.count)" }
                        " rows returned in "
                        HTMLElement(tag: "strong") { String(format: "%.3fs", model.elapsedSeconds) }
                    }
                    
                    Div(attributes: ["class": "scroll-container bg-white rounded"]) {
                        Table(attributes: ["class": "table table-sm table-bordered table-striped results-table mb-0"]) {
                            Thead(attributes: ["class": "sticky-header"]) {
                                Tr {
                                    for col in model.columns {
                                        Th(attributes: ["class": "p-2 border"]) { col }
                                    }
                                }
                            }
                            Tbody {
                                for row in model.rows {
                                    Tr {
                                        for cell in row {
                                            Td(attributes: ["class": "p-2 border text-nowrap"]) { cell ?? "NULL" }
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else if !model.sql.isEmpty && model.error == nil && model.elapsedSeconds > 0 {
                    Div(attributes: ["class": "alert alert-info"]) { "Query executed successfully but returned no rows." }
                }
            }
        }
    }
}
