const std = @import("std");

const html = @import("../html/html.zig");
const c = html.c;

pub const SearchEntry = struct {
    category: []const u8 = "",
    name: []const u8 = "",
    url: []const u8 = "",
    torrent_link: []const u8 = "",
    magnet_link: []const u8 = "",
    size: []const u8 = "",
    date: []const u8 = "",
    seeder: u32 = 0,
    leecher: u32 = 0,
    download: u32 = 0,
};

fn tdText(tds: [*c]c.lxb_dom_collection_t, idx: usize) []const u8 {
    return html.dom_element_text_content(c.lxb_dom_collection_element(tds, idx)) orelse "";
}

// nyaa.si category path -> label (matches `title` attr of the category <a>)
const category_labels = std.StaticStringMap([]const u8).initComptime(.{
    .{ "/?c=1_2", "Anime - English-translated" },
    .{ "/?c=1_3", "Anime - Non-English-translated" },
    .{ "/?c=1_4", "Anime - Raw" },
    .{ "/?c=2_2", "Audio - Lossless" },
    .{ "/?c=2_3", "Audio - Lossy" },
    .{ "/?c=3_2", "Literature - English-translated" },
    .{ "/?c=3_3", "Literature - Non-English-translated" },
    .{ "/?c=3_4", "Literature - Raw" },
    .{ "/?c=4_2", "Live Action - English-translated" },
    .{ "/?c=4_3", "Live Action - Non-English-translated" },
    .{ "/?c=4_4", "Live Action - Raw" },
    .{ "/?c=5_1", "Pictures - Graphics" },
    .{ "/?c=5_2", "Pictures - Photos" },
    .{ "/?c=6_1", "Software - Applications" },
    .{ "/?c=6_2", "Software - Games" },
});

pub fn categoryLabel(path: []const u8) []const u8 {
    return category_labels.get(path) orelse "Unknown";
}

fn tdCount(tds: [*c]c.lxb_dom_collection_t, idx: usize) u32 {
    const text = std.mem.trim(u8, tdText(tds, idx), " \n\r\t");
    return std.fmt.parseInt(u32, text, 10) catch 0;
}

pub fn searchRaw(io: std.Io, allocator: std.mem.Allocator) ![]u8 {
    var file = try std.Io.Dir.cwd().openFile(io, "log/nyaa.si", .{ .mode = .read_only });
    defer file.close(io);

    var buf = [1]u8{0};
    var file_reader = file.readerStreaming(io, &buf);

    const file_stat = try file.stat(io);
    const file_size = file_stat.size;

    const file_content = try file_reader.interface.readAlloc(allocator, file_size);

    return file_content;
}

const FindToListContext = struct { list: std.ArrayList([*c]c.struct_lxb_dom_node) };

pub fn find_callback(node: [*c]c.struct_lxb_dom_node, spec: c.lxb_css_selector_specificity_t, ctx: ?*anyopaque) callconv(.c) c_uint {
    _ = spec;

    var Context: *FindToListContext = @ptrCast(@alignCast(ctx));
    Context.list.appendAssumeCapacity(node);

    return 0;
}

// 84.5 MiB
// parse text size to bytes
fn parseSize(text: []const u8) !usize {
    const spaceSplit = std.mem.splitAny(u8, text, " ");

    const value_str = spaceSplit.next().?;
    const unit = spaceSplit.next().?;

    const value = try std.fmt.parseFloat(f32, value_str);
    if (std.mem.eql(u8, unit, "MiB")) {
        return value * 1048576;
    }

    return error.UnitNotSupport;
}

pub fn search(io: std.Io, allocator: std.mem.Allocator) ![]SearchEntry {
    const raw_search = try searchRaw(io, allocator);

    const document = c.lxb_html_document_create();
    if (document == null) return error.lxbCreateFail;
    defer _ = c.lxb_html_document_destroy(document);

    try html.html_document_parse(document, raw_search);

    const parser = c.lxb_css_parser_create();
    if (parser == null) return error.lxbCreateFail;
    try html.ok(c.lxb_css_parser_init(parser, null), error.lxbInitFail);
    defer _ = c.lxb_css_parser_destroy(parser, true);

    const selectors = c.lxb_selectors_create();
    if (selectors == null) return error.lxbCreateFail;
    try html.ok(c.lxb_selectors_init(selectors), error.lxbInitFail);
    defer _ = c.lxb_selectors_destroy(selectors, true);

    const target = "table.torrent-list tbody tr";
    const list = html.css_selectors_parse(parser, target);
    try html.ok(parser.*.status, error.lxbCssSelectorsParseFail);

    var ctx = FindToListContext{ .list = try .initCapacity(allocator, 1024) };
    defer ctx.list.deinit(allocator);

    try html.ok(c.lxb_selectors_find(selectors, @ptrCast(document), list, find_callback, @ptrCast(&ctx)), error.lxbSelectorsFindFail);

    const as = c.lxb_dom_collection_create(@ptrCast(document));
    _ = c.lxb_dom_collection_init(as, 16);

    var entries: std.ArrayList(SearchEntry) = .empty;

    for (ctx.list.items) |node| {
        const tds = c.lxb_dom_collection_create(node.*.owner_document);
        _ = c.lxb_dom_collection_init(tds, 16);
        try html.dom_elements_by_tag_name(c.lxb_dom_interface_element(node), tds, "td");

        const column_size = c.lxb_dom_collection_length(tds);

        if (column_size < 8) {
            std.debug.print("column_size < 8; skipped\n", .{});
            continue;
        }
        if (column_size > 8) {
            std.debug.print("column_size > 8; warn\n", .{});
        }

        var entry: SearchEntry = .{};

        const td_category = c.lxb_dom_collection_element(tds, 0);

        _ = c.lxb_dom_collection_clean(as);
        try html.dom_elements_by_tag_name(c.lxb_dom_interface_element(td_category), as, "a");

        if (c.lxb_dom_collection_length(as) > 0) {
            entry.category = html.dom_element_get_attribute(c.lxb_dom_collection_element(as, 0), "href") orelse "";
        }

        const td_title = c.lxb_dom_collection_element(tds, 1);
        _ = c.lxb_dom_collection_clean(as);
        try html.dom_elements_by_tag_name(c.lxb_dom_interface_element(td_title), as, "a");

        if (c.lxb_dom_collection_length(as) > 0) {
            const anchor = c.lxb_dom_collection_element(as, 0);
            entry.name = html.dom_element_get_attribute(anchor, "title") orelse "";
            entry.url = html.dom_element_get_attribute(anchor, "href") orelse "";
        }

        const td_torrent = c.lxb_dom_collection_element(tds, 2);
        _ = c.lxb_dom_collection_clean(as);
        try html.dom_elements_by_tag_name(c.lxb_dom_interface_element(td_torrent), as, "a");

        if (c.lxb_dom_collection_length(as) > 1) {
            entry.torrent_link = html.dom_element_get_attribute(c.lxb_dom_collection_element(as, 0), "href") orelse "";
            entry.magnet_link = html.dom_element_get_attribute(c.lxb_dom_collection_element(as, 1), "href") orelse "";
        }

        entry.size = tdText(tds, 3);
        entry.date = tdText(tds, 4);
        entry.seeder = tdCount(tds, 5);
        entry.leecher = tdCount(tds, 6);
        entry.download = tdCount(tds, 7);

        try entries.append(allocator, entry);
    }

    return try entries.toOwnedSlice(allocator);
}
