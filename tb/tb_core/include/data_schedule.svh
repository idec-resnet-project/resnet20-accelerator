    // --------------------------------
    // Tensor addresses
    // --------------------------------
    typedef struct packed {
        int feature_index;
        int kernel_index;
        bit padded;
    } tap_t;

    function automatic int output_extent(input int extent, size, stride, pad);
        return (extent + 2 * pad - size) / stride + 1;
    endfunction

    function automatic int output_index(input int y, x, oc, width, channels);
        return (y * width + x) * channels + oc;
    endfunction

    function automatic tap_t schedule_tap(input layer_t layer, input int y, x, oc, tap);
        tap_t address;
        int area, ic, iy, ix;
        // Kernel taps traverse ic, ky, and kx. Feature storage is HWC.
        area = layer.size * layer.size;
        ic = tap / area;
        iy = y * layer.stride + (tap % area) / layer.size - layer.pad;
        ix = x * layer.stride + tap % layer.size - layer.pad;
        address.padded = iy < 0 || iy >= layer.height || ix < 0 || ix >= layer.width;
        address.feature_index = address.padded ? -1 :
                                output_index(iy, ix, ic, layer.width, layer.cin);
        address.kernel_index = layer.weight_base + oc * layer.cin * area + tap;
        return address;
    endfunction

    // --------------------------------
    // Address and padding checks
    // --------------------------------
    task automatic check_schedule;
        layer_t layer;
        tap_t address;
        layer = '{80, 4, 4, 2, 3, 3, 2, 1, 100};
        address = schedule_tap(layer, 0, 0, 1, 0);
        if (!address.padded || address.feature_index != -1 || address.kernel_index != 118)
            $fatal(1, "Schedule: padding or output-channel kernel offset");
        address = schedule_tap(layer, 0, 0, 1, 13);
        if (address.padded || address.feature_index != 1 || address.kernel_index != 131)
            $fatal(1, "Schedule: input-channel or kernel tap offset");
        address = schedule_tap(layer, 1, 1, 2, 0);
        if (address.padded || address.feature_index != 10 || address.kernel_index != 136 ||
            output_index(1, 1, 2, 2, 3) != 11 || output_extent(4, 3, 2, 1) != 2)
            $fatal(1, "Schedule: stride or HWC indexing");
        $display("[ PASS ] schedule addressing and padding");
    endtask
