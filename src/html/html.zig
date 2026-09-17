const std = @import("std");

pub const c = @cImport({
    {
        @cInclude("lexbor/html/html.h");
        @cInclude("lexbor/css/css.h");
        @cInclude("lexbor/selectors/selectors.h");
    }
});

pub fn ok(status: c_uint, err: ?anyerror) !void {
    if (status != c.LXB_STATUS_OK) return err orelse error.lxbFail;
    return;
}

pub fn dom_element_get_attribute(
    element: [*c]c.struct_lxb_dom_element,
    qualified_name: []const u8,
) ?[]const u8 {
    var len: usize = 0;
    const text = c.lxb_dom_element_get_attribute(element, qualified_name.ptr, qualified_name.len, &len);

    if (len == 0) return null;
    return text[0..len];
}

pub fn dom_element_text_content(
    element: [*c]c.struct_lxb_dom_element,
) ?[]const u8 {
    var len: usize = 0;
    const text = c.lxb_dom_node_text_content(@ptrCast(element), &len);

    if (len == 0) return null;
    return text[0..len];
}

pub fn html_document_parse(
    document: [*c]c.struct_lxb_html_document,
    text: []const u8,
) !void {
    try ok(c.lxb_html_document_parse(document, text.ptr, text.len), error.lxbDocumentParseFail);
}

pub fn css_selectors_parse(
    parser: [*c]c.struct_lxb_css_parser,
    selector: []const u8,
) [*c]c.lxb_css_selector_list_t {
    return c.lxb_css_selectors_parse(parser, selector.ptr, selector.len);
}

pub fn dom_elements_by_tag_name(
    root: [*c]c.struct_lxb_dom_element,
    collection: [*c]c.lxb_dom_collection_t,
    qualified_name: []const u8,
) !void {
    try ok(c.lxb_dom_elements_by_tag_name(root, collection, qualified_name.ptr, qualified_name.len), error.lxbElementsByTagNameFail);
}
