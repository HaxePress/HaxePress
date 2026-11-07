package hx.press.database;

import hx.well.facades.Schema;

/**
    MCP links of administrators. They live in the database, so a link keeps
    its chosen lifetime across restarts and works on PHP, where every
    request is a new process.
**/
class AdminMcpSchema {
    public static function up():Void {
        if (Schema.hasTable("admin_mcp_links")) {
            return;
        }
        Schema.create("admin_mcp_links", table -> {
            table.string("id", 32).primary();
            table.bigInteger("admin_id").unsigned();
            table.string("auth_version", 64);
            table.string("profile", 16);
            table.string("origin", 255);
            table.string("token_hash", 64).unique();
            table.double("expires_epoch");
            table.double("first_seen_epoch").defaultValue(0);
            table.double("last_seen_epoch").defaultValue(0);
            table.double("created_epoch");
            table.index(["admin_id", "expires_epoch", "created_epoch"]);
            table.index(["expires_epoch"]);
            table.foreign("admin_id").references("id").on("admins").cascadeOnDelete();
        });
    }
}
