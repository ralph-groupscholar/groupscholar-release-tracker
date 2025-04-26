const std = @import("std");

pub const Record = struct {
    id: u64,
    name: []const u8,
    doc_type: []const u8,
    contact: []const u8,
    due_date: []const u8,
    status: []const u8,
    notes: []const u8,
    created_at: []const u8,
};

pub const Database = struct {
    next_id: u64,
    records: []Record,
};

pub const SyncDefaults = struct {
    pub const schema = "groupscholar_release_tracker";
    pub const table = "release_records";
};

pub const AddInput = struct {
    name: []const u8,
    doc_type: []const u8,
    contact: []const u8,
    due_date: []const u8,
    status: []const u8,
    notes: []const u8,
};

pub const UpdateInput = struct {
    id: u64,
    status: []const u8,
    notes: ?[]const u8,
};

pub fn initDatabase() Database {
    return Database{
        .next_id = 1,
        .records = &[_]Record{},
    };
}

pub fn loadDatabase(allocator: std.mem.Allocator, path: []const u8) !std.json.Parsed(Database) {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const data = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    return std.json.parseFromSlice(Database, allocator, data, .{});
}

pub fn saveDatabase(path: []const u8, db: Database) !void {
    var buffer = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer buffer.deinit();

    try std.json.stringify(db, .{ .whitespace = .indent_2 }, buffer.writer());

    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(buffer.items);
}

pub fn addRecord(allocator: std.mem.Allocator, db: *Database, input: AddInput, now_seconds: i64) !void {
    var list = std.array_list.Managed(Record).init(allocator);
    try list.appendSlice(db.records);

    const record = Record{
        .id = db.next_id,
        .name = try allocator.dupe(u8, input.name),
        .doc_type = try allocator.dupe(u8, input.doc_type),
        .contact = try allocator.dupe(u8, input.contact),
        .due_date = try allocator.dupe(u8, input.due_date),
        .status = try allocator.dupe(u8, input.status),
        .notes = try allocator.dupe(u8, input.notes),
        .created_at = try std.fmt.allocPrint(allocator, "{d}", .{now_seconds}),
    };

    try list.append(record);
    db.records = try list.toOwnedSlice();
    db.next_id += 1;
}

pub fn updateRecord(allocator: std.mem.Allocator, db: *Database, input: UpdateInput) !bool {
    var found = false;
    for (db.records) |*record| {
        if (record.id == input.id) {
            record.status = try allocator.dupe(u8, input.status);
            if (input.notes) |notes| {
                record.notes = try allocator.dupe(u8, notes);
            }
            found = true;
            break;
        }
    }
    return found;
}

pub fn isValidStatus(value: []const u8) bool {
    return std.mem.eql(u8, value, "pending") or
        std.mem.eql(u8, value, "received") or
        std.mem.eql(u8, value, "approved") or
        std.mem.eql(u8, value, "expired");
}

pub fn isValidDate(value: []const u8) bool {
    if (value.len != 10) return false;
    var i: usize = 0;
    while (i < value.len) : (i += 1) {
        if (i == 4 or i == 7) {
            if (value[i] != '-') return false;
            continue;
        }
        if (value[i] < '0' or value[i] > '9') return false;
    }
    return true;
}

pub fn countStatus(records: []const Record, status: []const u8) usize {
    var total: usize = 0;
    for (records) |record| {
        if (std.mem.eql(u8, record.status, status)) total += 1;
    }
    return total;
}

pub fn findEarliestDue(records: []const Record) ?[]const u8 {
    var earliest: ?[]const u8 = null;
    for (records) |record| {
        if (earliest == null) {
            earliest = record.due_date;
            continue;
        }
        if (std.mem.order(u8, record.due_date, earliest.?) == .lt) {
            earliest = record.due_date;
        }
    }
    return earliest;
}

pub fn matchesStatus(record: Record, filter: ?[]const u8) bool {
    if (filter == null) return true;
    return std.mem.eql(u8, record.status, filter.?);
}

pub fn expireRecords(allocator: std.mem.Allocator, db: *Database, as_of: []const u8) !usize {
    var expired: usize = 0;
    for (db.records) |*record| {
        if (std.mem.eql(u8, record.status, "approved")) continue;
        if (std.mem.eql(u8, record.status, "expired")) continue;
        if (std.mem.order(u8, record.due_date, as_of) == .lt) {
            record.status = "expired";
            expired += 1;
        }
    }
    return expired;
}

pub fn formatRecordLine(allocator: std.mem.Allocator, record: Record) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        "#{d} {s} | {s} | {s} | due {s} | {s}",
        .{ record.id, record.name, record.doc_type, record.contact, record.due_date, record.status },
    );
}

pub fn formatReportLine(allocator: std.mem.Allocator, label: []const u8, count: usize) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}: {d}", .{ label, count });
}

pub fn formatUsage(allocator: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        \\groupscholar-release-tracker
        \\\n        \\Usage:
        \\  release-tracker init <data.json>
        \\  release-tracker add <data.json> --name NAME --type TYPE --contact CONTACT --due YYYY-MM-DD [--status STATUS] [--notes NOTES]
        \\  release-tracker update <data.json> --id ID --status STATUS [--notes NOTES]
        \\  release-tracker list <data.json> [--status STATUS]
        \\  release-tracker report <data.json>
        \\  release-tracker expire <data.json> --as-of YYYY-MM-DD
        \\  release-tracker sync <data.json> [--schema NAME] [--table NAME]
        \\  release-tracker help
        ,
        .{},
    );
}

pub fn parseId(raw: []const u8) ?u64 {
    return std.fmt.parseInt(u64, raw, 10) catch null;
}

pub fn getOption(args: []const []const u8, key: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], key)) {
            if (i + 1 >= args.len) return null;
            return args[i + 1];
        }
    }
    return null;
}

pub fn requireOption(args: []const []const u8, key: []const u8) ![]const u8 {
    return getOption(args, key) orelse error.MissingOption;
}

pub fn requirePath(args: []const []const u8) ![]const u8 {
    if (args.len < 2) return error.MissingPath;
    return args[1];
}

pub fn requireCommand(args: []const []const u8) ![]const u8 {
    if (args.len < 1) return error.MissingCommand;
    return args[0];
}

pub fn statusOrDefault(args: []const []const u8) []const u8 {
    return getOption(args, "--status") orelse "pending";
}

pub fn notesOrDefault(args: []const []const u8) []const u8 {
    return getOption(args, "--notes") orelse "";
}

pub fn statusFilter(args: []const []const u8) ?[]const u8 {
    return getOption(args, "--status");
}

pub fn optionsSlice(args: []const []const u8) []const []const u8 {
    if (args.len <= 2) return &[_][]const u8{};
    return args[2..];
}

pub fn ensureStatus(status: []const u8) !void {
    if (!isValidStatus(status)) return error.InvalidStatus;
}

pub fn ensureDate(date: []const u8) !void {
    if (!isValidDate(date)) return error.InvalidDate;
}

pub fn isValidIdentifier(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value, 0..) |ch, idx| {
        if ((ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or ch == '_') {
            continue;
        }
        if (idx > 0 and (ch >= '0' and ch <= '9')) continue;
        return false;
    }
    return true;
}

pub fn ensureIdentifier(value: []const u8) !void {
    if (!isValidIdentifier(value)) return error.InvalidIdentifier;
}

pub fn escapeSqlString(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var buffer = std.array_list.Managed(u8).init(allocator);
    for (value) |ch| {
        if (ch == '\'') {
            try buffer.append('\'');
            try buffer.append('\'');
        } else {
            try buffer.append(ch);
        }
    }
    return buffer.toOwnedSlice();
}

pub fn formatSyncSql(
    allocator: std.mem.Allocator,
    db: Database,
    schema: []const u8,
    table: []const u8,
) ![]const u8 {
    var buffer = std.array_list.Managed(u8).init(allocator);
    const writer = buffer.writer();

    try writer.print("BEGIN;\n", .{});
    try writer.print("CREATE SCHEMA IF NOT EXISTS {s};\n", .{schema});
    try writer.print(
        "CREATE TABLE IF NOT EXISTS {s}.{s} (\n",
        .{ schema, table },
    );
    try writer.print("  id bigint PRIMARY KEY,\n", .{});
    try writer.print("  name text NOT NULL,\n", .{});
    try writer.print("  doc_type text NOT NULL,\n", .{});
    try writer.print("  contact text NOT NULL,\n", .{});
    try writer.print("  due_date date NOT NULL,\n", .{});
    try writer.print("  status text NOT NULL,\n", .{});
    try writer.print("  notes text NOT NULL,\n", .{});
    try writer.print("  created_at timestamptz NOT NULL\n", .{});
    try writer.print(");\n", .{});

    for (db.records) |record| {
        const name = try escapeSqlString(allocator, record.name);
        const doc_type = try escapeSqlString(allocator, record.doc_type);
        const contact = try escapeSqlString(allocator, record.contact);
        const due_date = try escapeSqlString(allocator, record.due_date);
        const status = try escapeSqlString(allocator, record.status);
        const notes = try escapeSqlString(allocator, record.notes);

        const created_seconds = std.fmt.parseInt(i64, record.created_at, 10) catch -1;
        const created_expr = if (created_seconds >= 0)
            try std.fmt.allocPrint(allocator, "to_timestamp({d})", .{created_seconds})
        else
            "now()";

        try writer.print(
            "INSERT INTO {s}.{s} (id, name, doc_type, contact, due_date, status, notes, created_at)\n",
            .{ schema, table },
        );
        try writer.print(
            "VALUES ({d}, '{s}', '{s}', '{s}', '{s}', '{s}', '{s}', {s})\n",
            .{ record.id, name, doc_type, contact, due_date, status, notes, created_expr },
        );
        try writer.print(
            "ON CONFLICT (id) DO UPDATE SET\n",
            .{},
        );
        try writer.print(
            "  name = EXCLUDED.name,\n",
            .{},
        );
        try writer.print(
            "  doc_type = EXCLUDED.doc_type,\n",
            .{},
        );
        try writer.print(
            "  contact = EXCLUDED.contact,\n",
            .{},
        );
        try writer.print(
            "  due_date = EXCLUDED.due_date,\n",
            .{},
        );
        try writer.print(
            "  status = EXCLUDED.status,\n",
            .{},
        );
        try writer.print(
            "  notes = EXCLUDED.notes,\n",
            .{},
        );
        try writer.print(
            "  created_at = EXCLUDED.created_at;\n",
            .{},
        );
    }

    try writer.print("COMMIT;\n", .{});

    return buffer.toOwnedSlice();
}

test "status validation" {
    try std.testing.expect(isValidStatus("pending"));
    try std.testing.expect(isValidStatus("received"));
    try std.testing.expect(!isValidStatus("unknown"));
}

test "date validation" {
    try std.testing.expect(isValidDate("2026-02-08"));
    try std.testing.expect(!isValidDate("02-08-2026"));
}

test "identifier validation" {
    try std.testing.expect(isValidIdentifier("groupscholar_release_tracker"));
    try std.testing.expect(isValidIdentifier("_tracker_01"));
    try std.testing.expect(!isValidIdentifier("1bad"));
    try std.testing.expect(!isValidIdentifier("bad-hyphen"));
}

test "sql escaping" {
    const escaped = try escapeSqlString(std.testing.allocator, "O'Reilly");
    defer std.testing.allocator.free(escaped);
    try std.testing.expectEqualStrings("O''Reilly", escaped);
}

test "expire records" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var records = [_]Record{
        .{
            .id = 1,
            .name = "A",
            .doc_type = "Photo",
            .contact = "a@example.com",
            .due_date = "2026-01-10",
            .status = "pending",
            .notes = "",
            .created_at = "0",
        },
        .{
            .id = 2,
            .name = "B",
            .doc_type = "Video",
            .contact = "b@example.com",
            .due_date = "2026-03-01",
            .status = "received",
            .notes = "",
            .created_at = "0",
        },
        .{
            .id = 3,
            .name = "C",
            .doc_type = "Photo",
            .contact = "c@example.com",
            .due_date = "2026-01-05",
            .status = "approved",
            .notes = "",
            .created_at = "0",
        },
    };
    var db = Database{
        .next_id = 4,
        .records = records[0..],
    };

    const expired = try expireRecords(arena.allocator(), &db, "2026-02-01");
    try std.testing.expectEqual(@as(usize, 1), expired);
    try std.testing.expectEqualStrings("expired", db.records[0].status);
    try std.testing.expectEqualStrings("received", db.records[1].status);
    try std.testing.expectEqualStrings("approved", db.records[2].status);
}
