package hx.press.database;

import haxe.extern.EitherType;

/** JDBC returns Date values; existing SQLite TEXT date columns return strings. */
typedef DatabaseDate = EitherType<Date, String>;
