const std = @import("std");

const html = @import("../html/html.zig");
const c = html.c;

pub const SearchEntry = struct {
    category: []u8 = "",
    name: []u8 = "",
    torrent_link: []u8,
    magnet_link: []u8 = "",
    size: []u8 = "",
    date: []u8,
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

        const td_category = c.lxb_dom_collection_element(tds, 0);
        const td_nyaa_page = c.lxb_dom_collection_element(tds, 1);
        const td_torrent = c.lxb_dom_collection_element(tds, 2);
        const td_size = c.lxb_dom_collection_element(tds, 3);
        const td_timestamp = c.lxb_dom_collection_element(tds, 4);
        const td_seeder = c.lxb_dom_collection_element(tds, 5);
        const td_leecher = c.lxb_dom_collection_element(tds, 6);
        const td_download = c.lxb_dom_collection_element(tds, 7);

        for (0..c.lxb_dom_collection_length(tds)) |idx| {
            const td = c.lxb_dom_collection_element(tds, idx);

            std.debug.print("td {d}:\n", .{idx});
            var child: [*c]c.struct_lxb_dom_node = td.*.node.first_child;
            while (child != null) : (child = child.*.next) {
                if (child.*.type != c.LXB_DOM_NODE_TYPE_ELEMENT) continue;
                if (child.*.local_name != c.LXB_TAG_A) continue;

                const a = c.lxb_dom_interface_element(child);
                const href = html.dom_element_get_attribute(a, "href");
                std.debug.print("  href: {s}\n", .{href orelse "null"});
            }
        }
    }
}
