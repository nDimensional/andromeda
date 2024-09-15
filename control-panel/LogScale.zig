const std = @import("std");
const gtk = @import("gtk");
const glib = @import("glib");
const gobject = @import("gobject");

const TEMPLATE = @embedFile("./data/ui/LogScale.xml");
const EXPONENT = 10;
const MIN_POW = 1;

inline fn getPow(value: f64) f64 {
    return std.math.floor(std.math.log10(value)) + 1;
}

pub const LogScale = extern struct {
    parent_instance: Parent,

    pub const Parent = gtk.Widget;

    const Private = struct {
        box: *gtk.Box,
        scale: *gtk.Scale,
        adjustment: *gtk.Adjustment,
        scale_inc: *gtk.Button,
        scale_dec: *gtk.Button,

        pow: f64,
        var offset: c_int = 0;
    };

    pub const getGObjectType = gobject.ext.defineClass(LogScale, .{
        .name = "LogScale",
        .instanceInit = &init,
        .classInit = &Class.init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    pub const signals = struct {
        pub const value_changed = struct {
            pub const name = "value_changed";
            pub const connect = impl.connect;
            const impl = gobject.ext.defineSignal(name, LogScale, &.{f64}, void);
        };
    };

    pub fn new() *LogScale {
        return LogScale.newWith(.{});
    }

    pub fn as(ls: *LogScale, comptime T: type) *T {
        return gobject.ext.as(T, ls);
    }

    pub fn getValue(ls: *LogScale) f64 {
        return ls.private().scale.as(gtk.Range).getValue();
    }

    pub fn setValue(ls: *LogScale, value: f64) void {
        const upper = ls.private().adjustment.getUpper();
        if (value > upper) {
            ls.setPow(getPow(value));
        }

        ls.private().scale.as(gtk.Range).setValue(value);
    }

    fn init(ls: *LogScale, _: *Class) callconv(.C) void {
        gtk.Widget.initTemplate(ls.as(gtk.Widget));
        gtk.Widget.setLayoutManager(ls.as(gtk.Widget), gtk.BinLayout.new().as(gtk.LayoutManager));

        _ = gtk.Button.signals.clicked.connect(ls.private().scale_inc, *LogScale, &handleScaleInc, ls, .{});
        _ = gtk.Button.signals.clicked.connect(ls.private().scale_dec, *LogScale, &handleScaleDec, ls, .{});

        const value = 22;
        const pow = getPow(value);
        ls.private().pow = pow;

        const range = ls.private().scale.as(gtk.Range);

        const upper = std.math.pow(f64, EXPONENT, pow);
        const step = std.math.pow(f64, EXPONENT, pow - 2);
        const page = std.math.pow(f64, EXPONENT, pow - 1);
        const adjustment = gtk.Adjustment.new(0, 0, upper, step, page, 0);
        range.setAdjustment(adjustment);
        ls.private().adjustment = adjustment;

        range.setValue(value);

        _ = gtk.Range.signals.value_changed.connect(range, *LogScale, &handleValueChanged, ls, .{});
    }

    fn dispose(ls: *LogScale) callconv(.C) void {
        gtk.Widget.disposeTemplate(ls.as(gtk.Widget), getGObjectType());
        gobject.Object.virtual_methods.dispose.call(Class.parent.as(gobject.Object.Class), ls.as(gobject.Object));
    }

    fn finalize(ls: *LogScale) callconv(.C) void {
        Class.parent.as(gobject.Object.Class).finalize.?(ls.as(gobject.Object));
    }

    fn handleValueChanged(range: *gtk.Range, ls: *LogScale) callconv(.C) void {
        signals.value_changed.impl.emit(ls, null, .{range.getValue()}, null);
    }

    fn handleScaleInc(_: *gtk.Button, ls: *LogScale) callconv(.C) void {
        ls.setPow(ls.private().pow + 1);
    }

    fn handleScaleDec(_: *gtk.Button, ls: *LogScale) callconv(.C) void {
        const pow = ls.private().pow;
        if (pow <= MIN_POW) return;

        const range = ls.private().scale.as(gtk.Range);

        const new_pow = pow - 1;
        const new_upper = std.math.pow(f64, EXPONENT, new_pow);
        const value = range.getValue();
        if (new_upper < value) range.setValue(new_upper);
        ls.setPow(new_pow);
    }

    fn setPow(ls: *LogScale, pow: f64) void {
        ls.private().pow = pow;

        const upper = std.math.pow(f64, EXPONENT, pow);
        const lower = 0;
        const step = std.math.pow(f64, EXPONENT, pow - 2);
        const page = std.math.pow(f64, EXPONENT, pow - 1);

        const adjustment = ls.private().adjustment;
        adjustment.setLower(lower);
        adjustment.setUpper(upper);
        adjustment.setStepIncrement(step);
        adjustment.setPageIncrement(page);
    }

    fn private(ls: *LogScale) *Private {
        return gobject.ext.impl_helpers.getPrivate(ls, Private, Private.offset);
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,

        var parent: *Parent.Class = undefined;

        pub const Instance = LogScale;

        pub fn as(class: *Class, comptime T: type) *T {
            return gobject.ext.as(T, class);
        }

        fn init(class: *Class) callconv(.C) void {
            gobject.Object.virtual_methods.dispose.implement(class, &dispose);
            gobject.Object.virtual_methods.finalize.implement(class, &finalize);
            // gtk.Widget.Class.setTemplateFromResource(class.as(gtk.Widget.Class), TEMPLATE_PATH);
            const template = glib.Bytes.newStatic(TEMPLATE.ptr, TEMPLATE.len);
            class.as(gtk.Widget.Class).setTemplate(template);

            class.bindTemplateChildPrivate("box", .{});
            class.bindTemplateChildPrivate("scale", .{});
            class.bindTemplateChildPrivate("scale_dec", .{});
            class.bindTemplateChildPrivate("scale_inc", .{});

            signals.value_changed.impl.register(.{});
        }

        fn bindTemplateChildPrivate(class: *Class, comptime name: [:0]const u8, comptime options: gtk.ext.BindTemplateChildOptions) void {
            gtk.ext.impl_helpers.bindTemplateChildPrivate(class, name, Private, Private.offset, options);
        }
    };
};
