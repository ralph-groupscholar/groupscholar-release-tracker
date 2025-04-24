const std = @import("std");
const tracker = @import("groupscholar_release_tracker");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args_raw = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args_raw);

    const args = args_raw[1..];
    if (args.len == 0) {
        try printUsage(allocator, std.io.getStdOut().writer());
        return;
    }

    const command = tracker.requireCommand(args) catch |err| switch (err) {
        error.MissingCommand => {
            try printUsage(allocator, std.io.getStdOut().writer());
            return;
        },
        else => return err,
    };

    if (std.mem.eql(u8, command, "help")) {
        try printUsage(allocator, std.io.getStdOut().writer());
        return;
    }

    const path = tracker.requirePath(args) catch |err| switch (err) {
        error.MissingPath => {
            try printUsage(allocator, std.io.getStdErr().writer());
            return;
        },
        else => return err,
    };

    if (std.mem.eql(u8, command, "init")) {
        try handleInit(path);
        return;
    }

    if (std.mem.eql(u8, command, "add")) {
        try handleAdd(allocator, path, tracker.optionsSlice(args));
        return;
    }

    if (std.mem.eql(u8, command, "update")) {
        try handleUpdate(allocator, path, tracker.optionsSlice(args));
        return;
    }

    if (std.mem.eql(u8, command, "list")) {
        try handleList(allocator, path, tracker.optionsSlice(args));
        return;
    }

    if (std.mem.eql(u8, command, "report")) {
        try handleReport(allocator, path);
        return;
    }

    if (std.mem.eql(u8, command, "expire")) {
        try handleExpire(allocator, path, tracker.optionsSlice(args));
        return;
    }

    if (std.mem.eql(u8, command, "sync")) {
        try handleSync(allocator, path, tracker.optionsSlice(args));
        return;
    }

    try std.io.getStdErr().writer().print("Unknown command: {s}\n", .{command});
    try printUsage(allocator, std.io.getStdErr().writer());
}

fn handleInit(path: []const u8) !void {
    const db = tracker.initDatabase();
    try tracker.saveDatabase(path, db);
    try std.io.getStdOut().writer().print("Initialized {s}\n", .{path});
}

fn handleAdd(allocator: std.mem.Allocator, path: []const u8, options: []const []const u8) !void {
    const name = try tracker.requireOption(options, "--name");
    const doc_type = try tracker.requireOption(options, "--type");
    const contact = try tracker.requireOption(options, "--contact");
    const due_date = try tracker.requireOption(options, "--due");
    const status = tracker.statusOrDefault(options);
    const notes = tracker.notesOrDefault(options);

    try tracker.ensureStatus(status);
    try tracker.ensureDate(due_date);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parsed = try tracker.loadDatabase(arena.allocator(), path);
    defer parsed.deinit();

    var db = parsed.value;
    const now_seconds = std.time.timestamp();
    try tracker.addRecord(arena.allocator(), &db, .{
        .name = name,
        .doc_type = doc_type,
        .contact = contact,
        .due_date = due_date,
        .status = status,
        .notes = notes,
    }, now_seconds);

    try tracker.saveDatabase(path, db);
    try std.io.getStdOut().writer().print("Added record #{d}\n", .{db.next_id - 1});
}

fn handleUpdate(allocator: std.mem.Allocator, path: []const u8, options: []const []const u8) !void {
    const id_raw = try tracker.requireOption(options, "--id");
    const status = try tracker.requireOption(options, "--status");
    const notes = tracker.getOption(options, "--notes");

    try tracker.ensureStatus(status);

    const id = tracker.parseId(id_raw) orelse {
        try std.io.getStdErr().writer().print("Invalid id: {s}\n", .{id_raw});
        return;
    };

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parsed = try tracker.loadDatabase(arena.allocator(), path);
    defer parsed.deinit();

    var db = parsed.value;
    const found = try tracker.updateRecord(arena.allocator(), &db, .{
        .id = id,
        .status = status,
        .notes = notes,
    });

    if (!found) {
        try std.io.getStdErr().writer().print("Record not found for id {d}\n", .{id});
        return;
    }

    try tracker.saveDatabase(path, db);
    try std.io.getStdOut().writer().print("Updated record #{d}\n", .{id});
}

fn handleList(allocator: std.mem.Allocator, path: []const u8, options: []const []const u8) !void {
    const filter = tracker.statusFilter(options);
    if (filter) |status| {
        try tracker.ensureStatus(status);
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parsed = try tracker.loadDatabase(arena.allocator(), path);
    defer parsed.deinit();

    const db = parsed.value;
    const stdout = std.io.getStdOut().writer();

    var count: usize = 0;
    for (db.records) |record| {
        if (!tracker.matchesStatus(record, filter)) continue;
        const line = try tracker.formatRecordLine(arena.allocator(), record);
        try stdout.print("{s}\n", .{line});
        count += 1;
    }

    if (count == 0) {
        try stdout.print("No records found.\n", .{});
    }
}

fn handleReport(allocator: std.mem.Allocator, path: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parsed = try tracker.loadDatabase(arena.allocator(), path);
    defer parsed.deinit();

    const db = parsed.value;
    const stdout = std.io.getStdOut().writer();

    const total = db.records.len;
    const pending = tracker.countStatus(db.records, "pending");
    const received = tracker.countStatus(db.records, "received");
    const approved = tracker.countStatus(db.records, "approved");
    const expired = tracker.countStatus(db.records, "expired");

    const earliest = tracker.findEarliestDue(db.records) orelse "n/a";

    try stdout.print("Release tracker report\n", .{});
    try stdout.print("Total records: {d}\n", .{total});

    const pending_line = try tracker.formatReportLine(arena.allocator(), "Pending", pending);
    const received_line = try tracker.formatReportLine(arena.allocator(), "Received", received);
    const approved_line = try tracker.formatReportLine(arena.allocator(), "Approved", approved);
    const expired_line = try tracker.formatReportLine(arena.allocator(), "Expired", expired);

    try stdout.print("{s}\n{s}\n{s}\n{s}\n", .{ pending_line, received_line, approved_line, expired_line });
    try stdout.print("Earliest due date: {s}\n", .{earliest});
}

fn handleExpire(allocator: std.mem.Allocator, path: []const u8, options: []const []const u8) !void {
    const as_of = try tracker.requireOption(options, "--as-of");
    try tracker.ensureDate(as_of);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parsed = try tracker.loadDatabase(arena.allocator(), path);
    defer parsed.deinit();

    var db = parsed.value;
    const expired = try tracker.expireRecords(arena.allocator(), &db, as_of);

    if (expired == 0) {
        try std.io.getStdOut().writer().print("No records expired as of {s}.\n", .{as_of});
        return;
    }

    try tracker.saveDatabase(path, db);
    try std.io.getStdOut().writer().print("Expired {d} record(s) as of {s}.\n", .{ expired, as_of });
}

fn handleSync(allocator: std.mem.Allocator, path: []const u8, options: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const database_url = try requireEnv(arena.allocator(), "DATABASE_URL");
    const schema = try optionOrEnv(arena.allocator(), options, "--schema", "RELEASE_TRACKER_SCHEMA", tracker.SyncDefaults.schema);
    const table = try optionOrEnv(arena.allocator(), options, "--table", "RELEASE_TRACKER_TABLE", tracker.SyncDefaults.table);

    try tracker.ensureIdentifier(schema);
    try tracker.ensureIdentifier(table);

    var parsed = try tracker.loadDatabase(arena.allocator(), path);
    defer parsed.deinit();

    const sql = try tracker.formatSyncSql(arena.allocator(), parsed.value, schema, table);
    try runPsql(arena.allocator(), database_url, sql);

    try std.io.getStdOut().writer().print("Synced {d} records to {s}.{s}\n", .{ parsed.value.records.len, schema, table });
}

fn printUsage(allocator: std.mem.Allocator, writer: anytype) !void {
    const usage = try tracker.formatUsage(allocator);
    try writer.print("{s}\n", .{usage});
}

fn requireEnv(allocator: std.mem.Allocator, key: []const u8) ![]const u8 {
    return std.process.getEnvVarOwned(allocator, key) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => {
            try std.io.getStdErr().writer().print("Missing required env var: {s}\n", .{key});
            return error.MissingEnvVar;
        },
        else => return err,
    };
}

fn optionOrEnv(
    allocator: std.mem.Allocator,
    options: []const []const u8,
    option_key: []const u8,
    env_key: []const u8,
    default_value: []const u8,
) ![]const u8 {
    if (tracker.getOption(options, option_key)) |value| return value;
    return std.process.getEnvVarOwned(allocator, env_key) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => default_value,
        else => return err,
    };
}

fn runPsql(allocator: std.mem.Allocator, database_url: []const u8, sql: []const u8) !void {
    var argv = std.array_list.Managed([]const u8).init(allocator);
    defer argv.deinit();
    try argv.append("psql");
    try argv.append("-v");
    try argv.append("ON_ERROR_STOP=1");
    try argv.append("-q");
    try argv.append("-X");
    try argv.append("-d");
    try argv.append(database_url);

    var child = std.process.Child.init(argv.items, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    child.spawn() catch |err| switch (err) {
        error.FileNotFound => {
            try std.io.getStdErr().writer().print("psql not found in PATH.\n", .{});
            return error.MissingPsql;
        },
        else => return err,
    };

    if (child.stdin) |stdin| {
        try stdin.writeAll(sql);
        stdin.close();
    }

    const result = try child.wait();
    switch (result) {
        .Exited => |code| {
            if (code != 0) return error.SyncFailed;
        },
        else => return error.SyncFailed,
    }
}
