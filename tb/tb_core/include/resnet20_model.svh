    // --------------------------------
    // Model dimensions and opcodes
    // --------------------------------
    localparam int LAYER_COUNT = 30;
    localparam int LOGIT_COUNT = 10;
    localparam int WEIGHT_WORDS = 271690;
    localparam int MAX_TENSOR_WORDS = 32 * 32 * 16;
    localparam int OP_INPUT = 1, OP_SKIP = 128, OP_PROJECTION = 192;
    localparam int OP_FC_OUT = 66;
    localparam int FLAG_RESIDUAL = 32, FLAG_RELU = 16, FLAG_GAP = 4;

    typedef logic signed [15:0] word_t;
    typedef struct packed {
        int op, width, height, cin, cout, size, stride, pad, weight_base;
    } layer_t;

    // --------------------------------
    // Layer descriptors and tensor buffers
    // --------------------------------
    layer_t layers[0:LAYER_COUNT-1];
    string layer_name[0:LAYER_COUNT-1];
    word_t weights[0:WEIGHT_WORDS-1];
    word_t feature[0:MAX_TENSOR_WORDS-1];
    word_t shortcut[0:MAX_TENSOR_WORDS-1];
    int weights_consumed;

    // --------------------------------
    // Manifest and little-endian weights
    // --------------------------------
    task automatic read_model(input string weight_path);
        int fd, lo, hi, offset;
        string name, extra;
        layer_t layer;
        fd = $fopen("vectors/layers.txt", "r");
        if (!fd) $fatal(1, "Cannot open vectors/layers.txt");
        offset = 0;
        for (int i = 0; i < LAYER_COUNT; i++) begin
            if ($fscanf(fd, "%s %d %d %d %d %d %d %d %d %d", name, layer.op,
                        layer.width, layer.height, layer.cin, layer.cout, layer.size,
                        layer.stride, layer.pad, layer.weight_base) != 10)
                $fatal(1, "Invalid layer descriptor %0d", i);
            if (layer.weight_base != offset)
                $fatal(1, "%s: unexpected weight offset %0d", name, layer.weight_base);
            offset += layer.cin * layer.cout * layer.size * layer.size + layer.cout;
            layers[i] = layer;
            layer_name[i] = name;
        end
        if (offset != WEIGHT_WORDS || $fscanf(fd, "%s", extra) == 1)
            $fatal(1, "Layer manifest length or total weight count mismatch");
        $fclose(fd);

        fd = $fopen(weight_path, "rb");
        if (!fd) $fatal(1, "Cannot open %s", weight_path);
        for (int i = 0; i < WEIGHT_WORDS; i++) begin
            lo = $fgetc(fd);
            hi = $fgetc(fd);
            if (lo < 0 || hi < 0) $fatal(1, "Truncated weight.bin at word %0d", i);
            weights[i] = {hi[7:0], lo[7:0]};
        end
        if ($fgetc(fd) >= 0) $fatal(1, "Extra bytes in weight.bin");
        $fclose(fd);
    endtask

    // --------------------------------
    // Tensor vector loader
    // --------------------------------
    task automatic read_hex(input string path, input int count,
                            output word_t target[0:MAX_TENSOR_WORDS-1]);
        int fd;
        logic [31:0] value;
        string extra;
        if (count < 1 || count > MAX_TENSOR_WORDS) $fatal(1, "Invalid size for %s", path);
        fd = $fopen(path, "r");
        if (!fd) $fatal(1, "Cannot open %s", path);
        for (int i = 0; i < count; i++) begin
            if ($fscanf(fd, "%h", value) != 1 || $isunknown(value) || value > 32'hffff)
                $fatal(1, "%s: invalid or missing word %0d", path, i);
            target[i] = value[15:0];
        end
        if ($fscanf(fd, "%s", extra) == 1) $fatal(1, "%s: extra words", path);
        $fclose(fd);
    endtask
