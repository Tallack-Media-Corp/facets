/// Metal source, compiled once per process at runtime. Keeping it as a string means
/// the package needs no Metal build step, and the Quick Look extensions share it.
///
/// Positions are the only vertex data. Normals come from screen-space derivatives of
/// the view-space position, which gives the crisp faceted look of a printed part,
/// halves the memory a big mesh needs, and ignores the (often wrong) normals STL
/// files carry. Faces are lit from whichever side the camera sees, so meshes with
/// flipped triangles still read correctly.
enum ShaderSource {
    static let metal = """
    #include <metal_stdlib>
    using namespace metal;

    struct Frame {
        float4x4 view;
        float4x4 projection;
        float4 gridColor;
    };

    struct Part {
        float4x4 model;
        float4 color;
        float4 options; // x: 1 for wireframe lines
    };

    struct MeshOut {
        float4 position [[position]];
        float3 viewPosition;
    };

    vertex MeshOut mesh_vertex(const device packed_float3 *positions [[buffer(0)]],
                               constant Frame &frame [[buffer(1)]],
                               constant Part &part [[buffer(2)]],
                               uint vid [[vertex_id]]) {
        MeshOut out;
        float4 world = part.model * float4(float3(positions[vid]), 1.0);
        float4 viewPosition = frame.view * world;
        out.viewPosition = viewPosition.xyz;
        out.position = frame.projection * viewPosition;
        return out;
    }

    fragment float4 mesh_fragment(MeshOut in [[stage_in]],
                                  constant Part &part [[buffer(2)]]) {
        float3 base = part.color.rgb;
        if (part.options.x > 0.5) {
            return float4(base * 0.85 + 0.05, 1.0);
        }
        float3 n = normalize(cross(dfdx(in.viewPosition), dfdy(in.viewPosition)));
        float3 v = normalize(-in.viewPosition);
        if (dot(n, v) < 0.0) { n = -n; }

        // A studio rig in view space: key from upper left, soft fill from the right,
        // sky/ground ambient, a little specular and a rim to separate the silhouette.
        float3 key = normalize(float3(-0.45, 0.75, 0.55));
        float3 fill = normalize(float3(0.7, -0.15, 0.45));
        float keyLight = max(dot(n, key), 0.0);
        float fillLight = max(dot(n, fill), 0.0);
        float sky = 0.5 + 0.5 * n.y;
        float3 h = normalize(key + v);
        float specular = pow(max(dot(n, h), 0.0), 40.0) * 0.18;
        float rim = pow(1.0 - max(dot(n, v), 0.0), 3.0) * 0.18;

        float3 lit = base * (0.14 + 0.20 * sky + 0.70 * keyLight + 0.22 * fillLight + rim) + specular;
        return float4(lit, 1.0);
    }

    struct Grid {
        float4 color;
        float4 params;    // x: step (mm), y: line width (pixels), z: bed state (0 none, 1 fits, 2 too big)
        float4 rect;      // centre xy, half size xy
        float4 bed;       // bed min xy, max xy
        float4 bedColor;  // outline colour when the part is too big
    };

    struct GridOut {
        float4 position [[position]];
        float2 world;
    };

    vertex GridOut grid_vertex(const device packed_float3 *corners [[buffer(0)]],
                               constant Frame &frame [[buffer(1)]],
                               uint vid [[vertex_id]]) {
        GridOut out;
        float3 p = float3(corners[vid]);
        out.position = frame.projection * frame.view * float4(p, 1.0);
        out.world = p.xy;
        return out;
    }

    // Distance to the nearest line in pixels, turned into antialiased coverage.
    static float lineCoverage(float2 p, float step, float width) {
        float2 g = p / step;
        float2 d = max(fwidth(g), float2(1e-5));
        float2 a = abs(fract(g - 0.5) - 0.5) / (d * width);
        return 1.0 - min(min(a.x, a.y), 1.0);
    }

    fragment float4 grid_fragment(GridOut in [[stage_in]],
                                  constant Grid &grid [[buffer(3)]]) {
        float step = grid.params.x;
        float width = grid.params.y;
        float minor = lineCoverage(in.world, step, width);
        float major = lineCoverage(in.world, step * 5.0, width * 1.3);
        // Fine lines fade out when they'd crowd together at a distance.
        float2 density = fwidth(in.world / step);
        float crowding = 1.0 - smoothstep(0.15, 0.4, max(density.x, density.y));
        float lines = max(minor * 0.4 * crowding, major * 0.8);

        float2 t = abs(in.world - grid.rect.xy) / grid.rect.zw;
        float edge = 1.0 - smoothstep(0.55, 1.0, max(t.x, t.y));
        float a = grid.color.a * (lines + 0.10) * edge;
        float3 rgb = grid.color.rgb;

        float state = grid.params.z;
        if (state > 0.5) {
            // The chosen printer's bed: a firm outline, a slightly brighter plate
            // inside it, and the grid outside quieter, so the bed reads at a glance.
            float2 lo = grid.bed.xy, hi = grid.bed.zw;
            bool inside = all(in.world >= lo) && all(in.world <= hi);
            float2 d = min(abs(in.world - lo), abs(in.world - hi));
            float2 px = max(fwidth(in.world), float2(1e-5));
            float distX = (in.world.y >= lo.y - px.y && in.world.y <= hi.y + px.y) ? d.x / px.x : 1e6;
            float distY = (in.world.x >= lo.x - px.x && in.world.x <= hi.x + px.x) ? d.y / px.y : 1e6;
            float outline = 1.0 - smoothstep(width * 1.2, width * 2.2, min(distX, distY));
            a = inside ? a + grid.color.a * 0.10 : a * 0.45;
            float3 outlineRGB = state > 1.5 ? grid.bedColor.rgb : grid.color.rgb;
            float outlineA = state > 1.5 ? 0.95 : min(grid.color.a * 3.0, 0.8);
            rgb = mix(rgb, outlineRGB, outline);
            a = max(a, outline * outlineA);
        }
        return float4(rgb * a, a);
    }
    """
}
