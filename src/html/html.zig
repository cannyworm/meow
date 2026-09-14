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

pub fn MakeProxy(
    HandleType: type,
    //
    fnCreate: fn () callconv(.c) [*c]HandleType,
    fnInit: ?fn ([*c]HandleType) callconv(.c) c.lxb_status_t,
    fnDeinit: fn ([*c]HandleType) callconv(.c) [*c]HandleType,
    //
) type {
    return struct {
        handle: [*c]HandleType = null,
        pub fn create() !@This() {
            const handle = fnCreate();
            if (handle == null) return error.lxbCreateFail;
            return .{ .handle = handle };
        }
        pub fn init(self: @This()) !void {
            if (fnInit == null) return;

            return try ok(fnInit(self.handle), error.lxbInitFail);
        }

        pub fn createInit() !@This() {
            var this = try @This().create();
            try this.init();
            return this;
        }

        pub fn deinit(self: @This()) void {
            _ = fnDeinit(self.handle);
        }
    };
}

pub const HTMLDocument = MakeProxy(c.struct_lxb_html_document, c.lxb_html_document_create, null, c.lxb_html_document_destroy);
// pub const CSSParser = MakeProxy(c.struct_lxb_css_parser, c.lxb_css_parser_create, c.lxb_css_parser_init, c.lxb_css_parser_destroy);
// pub const Selectors = MakeProxy(c.struct_lxb_selectors, c.lxb_selectors_create, c.lxb_selectors_init, c.lxb_selectors_destroy);

pub fn dom_element_get_attribute(
    element: [*c]c.struct_lxb_dom_element,
    qualified_name: []const u8,
) ?[]const u8 {
    var len: usize = 0;
    const text = c.lxb_dom_element_get_attribute(element, qualified_name.ptr, qualified_name.len, &len);

    if (len == 0) return null;
    return text[0..len];
}
