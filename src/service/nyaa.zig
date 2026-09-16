const std = @import("std");

const html = @import("../html/html.zig");
const c = html.c;

pub const SearchEntry = struct {
    category: []const u8 = undefined,
    name: []const u8 = undefined,
    url: []const u8 = undefined,
    torrent_link: []const u8 = undefined,
    magnet_link: []const u8 = undefined,
    size: []const u8 = undefined,
    date: []const u8 = undefined,
    seeder: u32 = 0,
    leecher: u32 = 0,
    download: u32 = 0,
};

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

fn anchorHref(elementPtr: [*c]c.struct_lxb_dom_node) ?[]const u8 {
    const element = elementPtr.*;
    std.debug.print("{d} {d}\n", .{ element.type, element.local_name });
    if (element.type != c.LXB_DOM_NODE_TYPE_ELEMENT) return null;
    if (element.local_name != c.LXB_TAG_A) return null;

    const a = c.lxb_dom_interface_element(elementPtr);
    return html.dom_element_get_attribute(a, "href");
}

fn anchorTitle(elementPtr: [*c]c.struct_lxb_dom_node) ?[]const u8 {
    const element = elementPtr.*;
    if (element.type != c.LXB_DOM_NODE_TYPE_ELEMENT) return null;
    if (element.local_name != c.LXB_TAG_A) return null;

    const a = c.lxb_dom_interface_element(elementPtr);
    return html.dom_element_get_attribute(a, "title");
}

pub fn search(io: std.Io, allocator: std.mem.Allocator) !void {
    const raw_search = try searchRaw(io, allocator);

    const document = try html.HTMLDocument.createInit();
    defer document.deinit();

    try html.ok(c.lxb_html_document_parse(document.handle, raw_search.ptr, raw_search.len), error.lxbDocumentParseFail);

    const parser = c.lxb_css_parser_create();
    if (parser == null) return error.lxbCssParserCreateFail;

    try html.ok(c.lxb_css_parser_init(parser, null), error.lxbCssParserInitFail);

    const selectors = c.lxb_selectors_create();
    if (selectors == null) return error.lxdSelectorsCreateFail;
    try html.ok(c.lxb_selectors_init(selectors), error.lxbSelectorsInitFail);

    const target = "table.torrent-list tbody tr";
    const list = c.lxb_css_selectors_parse(parser, target, target.len);
    try html.ok(parser.*.status, error.lxbCssSelectorsParseFail);

    var ctx = FindToListContext{ .list = try .initCapacity(allocator, 1024) };
    defer ctx.list.deinit(allocator);

    try html.ok(c.lxb_selectors_find(selectors, @ptrCast(document.handle), list, find_callback, @ptrCast(&ctx)), error.lxbSelectorsFindFail);

    // var result: std.ArrayList(SearchEntry) = .initCapacity(allocator, 20);

    const as = c.lxb_dom_collection_create(document.handle);

    for (ctx.list.items) |node| {
        const tds = c.lxb_dom_collection_create(node.*.owner_document);
        _ = c.lxb_dom_collection_init(tds, 16);
        _ = c.lxb_dom_elements_by_tag_name(c.lxb_dom_interface_element(node), tds, "td", 2);

        const column_size = c.lxb_dom_collection_length(tds);

        if (column_size < 8) {
            std.debug.print("column_size < 7; skipped\n", .{});
            continue;
        }
        if (column_size > 8) {
            std.debug.print("column_size > 7; warn\n", .{});
        }

        // var entry: SearchEntry = .{};

        const td_category = c.lxb_dom_collection_element(tds, 0);
        _ = c.lxb_dom_collection_init(as, 16);
        _ = c.lxb_dom_elements_by_tag_name(c.lxb_dom_interface_element(td_category), as, "a", 1);
        for (0..c.lxb_dom_collection_length(as)) |idx| {
            const a = c.lxb_dom_collection_element(as, idx);
            std.debug.print("a {d}: {s}\n", .{ idx, html.dom_element_get_attribute(a, "href") orelse "null" });
        }
    }
}
