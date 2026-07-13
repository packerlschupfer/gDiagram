/* VennLayout.vala — Euler/Venn circle layout
 *
 * A port of @upsetjs/venn.js 2.0.0 (the layout Mermaid 12.2.0 uses for its
 * `venn-beta` diagram) together with the Nelder-Mead simplex optimiser of
 * fmin 0.0.2 that venn.js depends on. Ported files:
 *
 *   src/circleintersection.js  — circleArea, circleOverlap, intersectionArea,
 *                                circleCircleIntersection
 *   src/layout.js              — venn, greedyLayout, lossFunction,
 *                                distanceFromIntersectArea, disjointCluster,
 *                                normalizeSolution, scaleSolution
 *   src/diagram.js             — computeTextCentre, computeTextCentres
 *   fmin                       — nelderMead, bisect
 *
 * @upsetjs/venn.js and fmin are MIT licensed:
 *
 *   Copyright (c) 2013 Ben Frederickson
 *   Copyright (c) 2021 Samuel Gratzl
 *
 *   Permission is hereby granted, free of charge, to any person obtaining a
 *   copy of this software and associated documentation files (the "Software"),
 *   to deal in the Software without restriction, including without limitation
 *   the rights to use, copy, modify, merge, publish, distribute, sublicense,
 *   and/or sell copies of the Software, and to permit persons to whom the
 *   Software is furnished to do so, subject to the following conditions:
 *
 *   The above copyright notice and this permission notice shall be included in
 *   all copies or substantial portions of the Software.
 *
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 *   THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 *   DEALINGS IN THE SOFTWARE.
 *
 * Deliberately NOT ported (see MermaidVennRenderer.vala for the consequences):
 *   - constrainedMDSLayout: venn.js only tries it for 8+ areas and only keeps
 *     it when it beats greedy; it needs a conjugate-gradient solver and uses
 *     Math.random, so it is not reproducible anyway.
 *   - (ported 2026-10-25) the multi-cluster packing of normalizeSolution:
 *     disjoint groups of circles are laid out side by side; we keep the largest
 *     orientation and let scaleSolution fit everything, which is identical for
 *     any diagram whose sets all overlap.
 *   - intersectionAreaPath / arcsToPath: mermaid draws intersection areas with
 *     fill-opacity 0 unless a `style` sets a fill, so the lens outlines are
 *     invisible by default.
 */
namespace GDiagram {

/** One laid-out circle. */
public class VennCircle : Object {
    public string setid { get; set; }
    public double x { get; set; }
    public double y { get; set; }
    public double radius { get; set; }
    public double size { get; set; }

    public VennCircle(string setid, double x, double y, double radius, double size = 0) {
        this.setid = setid;
        this.x = x;
        this.y = y;
        this.radius = radius;
        this.size = size;
    }

    public VennCircle copy() {
        return new VennCircle(setid, x, y, radius, size);
    }
}

/** An input area: the sets it covers and the area it should occupy. */
public class VennArea : Object {
    public string[] sets;
    public double size;
    public double weight;

    public VennArea(string[] sets, double size, double weight = 1.0) {
        this.sets = sets;
        this.size = size;
        this.weight = weight;
    }

    public string key() {
        return string.joinv(";", sets);
    }
}

/** The solution: circles by set id, in insertion order. */
public class VennSolution : Object {
    public Gee.ArrayList<VennCircle> circles { get; private set; }
    // Text anchor per area key ("A", "A|B"); x = -1e9 marks a disjoint area.
    public Gee.HashMap<string, double?> text_x { get; private set; }
    public Gee.HashMap<string, double?> text_y { get; private set; }

    public VennSolution() {
        this.circles = new Gee.ArrayList<VennCircle>();
        this.text_x = new Gee.HashMap<string, double?>();
        this.text_y = new Gee.HashMap<string, double?>();
    }

    public VennCircle? get_circle(string setid) {
        foreach (var c in circles) {
            if (c.setid == setid) return c;
        }
        return null;
    }
}

public class VennLayout : Object {

    private const double SMALL = 1e-10;

    /** A point with the indices of the two circles whose boundaries cross there. */
    private class VennPoint {
        public double x;
        public double y;
        public int pa;
        public int pb;
        public double angle;

        public VennPoint(double x, double y, int pa = -1, int pb = -1) {
            this.x = x;
            this.y = y;
            this.pa = pa;
            this.pb = pb;
            this.angle = 0;
        }

        public bool has_parent(int i) { return pa == i || pb == i; }
    }

    /** One arc of an intersection boundary. */
    private class VennArc {
        public VennCircle circle;
        public double width;
        public VennPoint p1;
        public VennPoint p2;

        public VennArc(VennCircle circle, double width, VennPoint p1, VennPoint p2) {
            this.circle = circle;
            this.width = width;
            this.p1 = p1;
            this.p2 = p2;
        }
    }

    // ── circleintersection.js ────────────────────────────────────

    public static double distance(double x1, double y1, double x2, double y2) {
        return Math.sqrt((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2));
    }

    /** Circular segment area: http://mathworld.wolfram.com/CircularSegment.html */
    public static double circle_area(double r, double width) {
        return r * r * Math.acos(1 - width / r)
             - (r - width) * Math.sqrt(width * (2 * r - width));
    }

    /** Overlap area of two circles of radius r1/r2 whose centres are d apart. */
    public static double circle_overlap(double r1, double r2, double d) {
        if (d >= r1 + r2) return 0;
        if (d <= Math.fabs(r1 - r2)) {
            double m = double.min(r1, r2);
            return Math.PI * m * m;
        }
        double w1 = r1 - (d * d - r2 * r2 + r1 * r1) / (2 * d);
        double w2 = r2 - (d * d - r1 * r1 + r2 * r2) / (2 * d);
        return circle_area(r1, w1) + circle_area(r2, w2);
    }

    private static Gee.ArrayList<VennPoint> circle_circle_intersection(
            double x1, double y1, double r1, double x2, double y2, double r2) {
        var ret = new Gee.ArrayList<VennPoint>();
        double d = distance(x1, y1, x2, y2);
        if (d >= r1 + r2 || d <= Math.fabs(r1 - r2)) return ret;

        double a = (r1 * r1 - r2 * r2 + d * d) / (2 * d);
        double h = Math.sqrt(r1 * r1 - a * a);
        double x0 = x1 + (a * (x2 - x1)) / d;
        double y0 = y1 + (a * (y2 - y1)) / d;
        double rx = -(y2 - y1) * (h / d);
        double ry = -(x2 - x1) * (h / d);
        ret.add(new VennPoint(x0 + rx, y0 - ry));
        ret.add(new VennPoint(x0 - rx, y0 + ry));
        return ret;
    }

    private static bool contained_in_circles(VennPoint p, Gee.List<VennCircle> circles) {
        foreach (var c in circles) {
            if (!(distance(p.x, p.y, c.x, c.y) < c.radius + SMALL)) return false;
        }
        return true;
    }

    /** Intersection area of an arbitrary set of circles; fills `arcs` when given. */
    private static double intersection_area(Gee.List<VennCircle> circles,
                                            Gee.ArrayList<VennArc>? arcs_out = null) {
        var ipoints = new Gee.ArrayList<VennPoint>();
        for (int i = 0; i < circles.size; i++) {
            for (int j = i + 1; j < circles.size; j++) {
                var a = circles.get(i);
                var b = circles.get(j);
                foreach (var p in circle_circle_intersection(a.x, a.y, a.radius, b.x, b.y, b.radius)) {
                    p.pa = i;
                    p.pb = j;
                    ipoints.add(p);
                }
            }
        }
        var inner = new Gee.ArrayList<VennPoint>();
        foreach (var p in ipoints) {
            if (contained_in_circles(p, circles)) inner.add(p);
        }

        double arc_area = 0, polygon_area = 0;
        Gee.ArrayList<VennArc> arcs = arcs_out;
        if (arcs == null) arcs = new Gee.ArrayList<VennArc>();

        if (inner.size > 1) {
            double ccx = 0, ccy = 0;
            foreach (var p in inner) { ccx += p.x; ccy += p.y; }
            ccx /= inner.size;
            ccy /= inner.size;
            foreach (var p in inner) {
                p.angle = Math.atan2(p.x - ccx, p.y - ccy);
            }
            // b.angle - a.angle: descending by angle, stably (JS sort is stable).
            for (int i = 1; i < inner.size; i++) {
                var cur = inner.get(i);
                int j = i - 1;
                while (j >= 0 && inner.get(j).angle < cur.angle) {
                    inner.set(j + 1, inner.get(j));
                    j--;
                }
                inner.set(j + 1, cur);
            }

            var p2 = inner.get(inner.size - 1);
            for (int i = 0; i < inner.size; i++) {
                var p1 = inner.get(i);
                polygon_area += (p2.x + p1.x) * (p1.y - p2.y);

                double mx = (p1.x + p2.x) / 2;
                double my = (p1.y + p2.y) / 2;
                VennArc? arc = null;

                for (int k = 0; k < 2; k++) {
                    int pi = k == 0 ? p1.pa : p1.pb;
                    if (pi < 0 || !p2.has_parent(pi)) continue;
                    var circle = circles.get(pi);
                    double a1 = Math.atan2(p1.x - circle.x, p1.y - circle.y);
                    double a2 = Math.atan2(p2.x - circle.x, p2.y - circle.y);
                    double angle_diff = a2 - a1;
                    if (angle_diff < 0) angle_diff += 2 * Math.PI;
                    double a = a2 - angle_diff / 2;
                    double width = distance(mx, my,
                        circle.x + circle.radius * Math.sin(a),
                        circle.y + circle.radius * Math.cos(a));
                    if (width > circle.radius * 2) width = circle.radius * 2;
                    if (arc == null || arc.width > width) {
                        arc = new VennArc(circle, width, p1, p2);
                    }
                }

                if (arc != null) {
                    arcs.add(arc);
                    arc_area += circle_area(arc.circle.radius, arc.width);
                    p2 = p1;
                }
            }
        } else {
            var smallest = circles.get(0);
            for (int i = 1; i < circles.size; i++) {
                if (circles.get(i).radius < smallest.radius) smallest = circles.get(i);
            }
            bool disjoint = false;
            foreach (var c in circles) {
                if (distance(c.x, c.y, smallest.x, smallest.y)
                        > Math.fabs(smallest.radius - c.radius)) {
                    disjoint = true;
                    break;
                }
            }
            if (disjoint) {
                arc_area = 0;
                polygon_area = 0;
            } else {
                arc_area = smallest.radius * smallest.radius * Math.PI;
                arcs.add(new VennArc(smallest, smallest.radius * 2,
                    new VennPoint(smallest.x, smallest.y + smallest.radius),
                    new VennPoint(smallest.x - SMALL, smallest.y + smallest.radius)));
            }
        }

        polygon_area /= 2;
        return arc_area + polygon_area;
    }

    // ── fmin ─────────────────────────────────────────────────────

    public delegate double VennObjective(double[] x);

    /** fmin's bisect: a root of `f` in [a, b]. */
    public static double bisect(VennObjective f, double a, double b,
                                double tolerance = 1e-10, int max_iterations = 100) {
        double[] pa = { a };
        double[] pb = { b };
        double fa = f(pa);
        double fb = f(pb);
        if (fa * fb > 0) return (a + b) / 2;   // same sign: no bracketed root
        for (int i = 0; i < max_iterations; i++) {
            double mid = (a + b) / 2;
            double[] pm = { mid };
            double fmid = f(pm);
            if (Math.fabs(b - a) < 2 * tolerance) return mid;
            if (fmid * fa < 0) {
                b = mid;
                fb = fmid;
            } else {
                a = mid;
                fa = fmid;
            }
        }
        return (a + b) / 2;
    }

    private class Simplex {
        public double[] p;
        public double fx;
        public Simplex(double[] p, double fx) { this.p = p; this.fx = fx; }
    }

    private static void weighted_sum(double[] ret, double w1, double[] v1, double w2, double[] v2) {
        for (int j = 0; j < ret.length; j++) {
            ret[j] = w1 * v1[j] + w2 * v2[j];
        }
    }

    /** fmin's nelderMead, with its default parameters. */
    public static double[] nelder_mead(VennObjective f, double[] x0,
                                       int max_iterations = 0,
                                       double min_error_delta = 1e-6) {
        int N = x0.length;
        if (max_iterations <= 0) max_iterations = N * 200;
        const double NON_ZERO_DELTA = 1.05;
        const double ZERO_DELTA = 0.001;
        double min_tolerance = min_error_delta;
        const double RHO = 1, CHI = 2, PSI = -0.5, SIGMA = 0.5;

        var simplex = new Simplex[N + 1];
        simplex[0] = new Simplex(copy_vec(x0), f(x0));
        for (int i = 0; i < N; i++) {
            double[] point = copy_vec(x0);
            point[i] = point[i] != 0 ? point[i] * NON_ZERO_DELTA : ZERO_DELTA;
            simplex[i + 1] = new Simplex(point, f(point));
        }

        double[] centroid = copy_vec(x0);
        double[] reflected = copy_vec(x0);
        double[] contracted = copy_vec(x0);
        double[] expanded = copy_vec(x0);

        for (int iteration = 0; iteration < max_iterations; iteration++) {
            sort_simplex(simplex);

            double max_diff = 0;
            for (int i = 0; i < N; i++) {
                max_diff = double.max(max_diff, Math.fabs(simplex[0].p[i] - simplex[1].p[i]));
            }
            if (Math.fabs(simplex[0].fx - simplex[N].fx) < min_error_delta
                    && max_diff < min_tolerance) {
                break;
            }

            for (int i = 0; i < N; i++) {
                centroid[i] = 0;
                for (int j = 0; j < N; j++) centroid[i] += simplex[j].p[i];
                centroid[i] /= N;
            }

            var worst = simplex[N];
            weighted_sum(reflected, 1 + RHO, centroid, -RHO, worst.p);
            double rfx = f(reflected);

            if (rfx < simplex[0].fx) {
                weighted_sum(expanded, 1 + CHI, centroid, -CHI, worst.p);
                double efx = f(expanded);
                simplex[N] = efx < rfx
                    ? new Simplex(copy_vec(expanded), efx)
                    : new Simplex(copy_vec(reflected), rfx);
            } else if (rfx >= simplex[N - 1].fx) {
                bool should_reduce = false;
                if (rfx > worst.fx) {
                    weighted_sum(contracted, 1 + PSI, centroid, -PSI, worst.p);
                    double cfx = f(contracted);
                    if (cfx < worst.fx) {
                        simplex[N] = new Simplex(copy_vec(contracted), cfx);
                    } else {
                        should_reduce = true;
                    }
                } else {
                    weighted_sum(contracted, 1 - PSI * RHO, centroid, PSI * RHO, worst.p);
                    double cfx = f(contracted);
                    if (cfx < rfx) {
                        simplex[N] = new Simplex(copy_vec(contracted), cfx);
                    } else {
                        should_reduce = true;
                    }
                }
                if (should_reduce) {
                    // SIGMA is 0.5, so the `sigma >= 1` early exit never fires.
                    for (int i = 1; i < simplex.length; i++) {
                        double[] tmp = copy_vec(simplex[i].p);
                        weighted_sum(tmp, 1 - SIGMA, simplex[0].p, SIGMA, simplex[i].p);
                        simplex[i] = new Simplex(tmp, f(tmp));
                    }
                }
            } else {
                simplex[N] = new Simplex(copy_vec(reflected), rfx);
            }
        }

        sort_simplex(simplex);
        return simplex[0].p;
    }

    private static double[] copy_vec(double[] v) {
        double[] r = new double[v.length];
        for (int i = 0; i < v.length; i++) r[i] = v[i];
        return r;
    }

    // Insertion sort: Array.prototype.sort is stable in V8, and the simplex is tiny.
    private static void sort_simplex(Simplex[] s) {
        for (int i = 1; i < s.length; i++) {
            var cur = s[i];
            int j = i - 1;
            while (j >= 0 && s[j].fx > cur.fx) {
                s[j + 1] = s[j];
                j--;
            }
            s[j + 1] = cur;
        }
    }

    // ── layout.js ────────────────────────────────────────────────

    /** Centre distance that gives two circles of radius r1/r2 the overlap `overlap`. */
    public static double distance_from_intersect_area(double r1, double r2, double overlap) {
        double m = double.min(r1, r2);
        if (m * m * Math.PI <= overlap + SMALL) return Math.fabs(r1 - r2);
        return bisect((d) => circle_overlap(r1, r2, d[0]) - overlap, 0, r1 + r2);
    }

    /** lossFunction: squared error between realised and requested areas. */
    private static double loss_function(Gee.ArrayList<VennCircle> circles,
                                        Gee.List<VennArea> overlaps) {
        double output = 0;
        foreach (var area in overlaps) {
            if (area.sets.length == 1) continue;
            double overlap;
            if (area.sets.length == 2) {
                var l = find(circles, area.sets[0]);
                var r = find(circles, area.sets[1]);
                overlap = circle_overlap(l.radius, r.radius, distance(l.x, l.y, r.x, r.y));
            } else {
                var members = new Gee.ArrayList<VennCircle>();
                foreach (string s in area.sets) members.add(find(circles, s));
                overlap = intersection_area(members);
            }
            output += area.weight * (overlap - area.size) * (overlap - area.size);
        }
        return output;
    }

    private static VennCircle find(Gee.ArrayList<VennCircle> circles, string setid) {
        foreach (var c in circles) {
            if (c.setid == setid) return c;
        }
        // Cannot happen: every set referenced by an area is declared.
        return new VennCircle(setid, 0, 0, 0);
    }

    /** addMissingAreas: an undeclared pair means two disjoint sets, i.e. overlap 0. */
    private static Gee.ArrayList<VennArea> add_missing_areas(Gee.List<VennArea> areas) {
        var r = new Gee.ArrayList<VennArea>();
        foreach (var a in areas) r.add(new VennArea(a.sets, a.size, a.weight));

        var ids = new Gee.ArrayList<string>();
        var pairs = new Gee.HashSet<string>();
        foreach (var a in r) {
            if (a.sets.length == 1) {
                ids.add(a.sets[0]);
            } else if (a.sets.length == 2) {
                pairs.add(a.sets[0] + ";" + a.sets[1]);
                pairs.add(a.sets[1] + ";" + a.sets[0]);
            }
        }
        ids.sort((a, b) => strcmp(a, b));
        for (int i = 0; i < ids.size; i++) {
            for (int j = i + 1; j < ids.size; j++) {
                string key = ids.get(i) + ";" + ids.get(j);
                if (!pairs.contains(key)) {
                    r.add(new VennArea({ ids.get(i), ids.get(j) }, 0));
                }
            }
        }
        return r;
    }

    private class Overlap {
        public string set;
        public double size;
        public double weight;
        public Overlap(string set, double size, double weight) {
            this.set = set;
            this.size = size;
            this.weight = weight;
        }
    }

    /**
     * greedyLayout: place the most-overlapped set at the origin, then each
     * remaining set at the candidate position (axis-aligned offsets plus the
     * analytic two-constraint solutions) with the lowest pairwise loss.
     *
     * The areas the loss sees here are only the pairwise ones, exactly as in
     * venn.js — the 3+-set terms come in during the nelderMead refinement.
     */
    private static Gee.ArrayList<VennCircle> greedy_layout(Gee.List<VennArea> areas) {
        var circles = new Gee.ArrayList<VennCircle>();
        var overlaps = new Gee.HashMap<string, Gee.ArrayList<Overlap>>();
        var order = new Gee.ArrayList<string>();

        foreach (var area in areas) {
            if (area.sets.length != 1) continue;
            string set = area.sets[0];
            var c = new VennCircle(set, 1e10, 1e10, Math.sqrt(area.size / Math.PI), area.size);
            circles.add(c);
            overlaps.set(set, new Gee.ArrayList<Overlap>());
            order.add(set);
        }

        var pairwise = new Gee.ArrayList<VennArea>();
        foreach (var a in areas) {
            if (a.sets.length == 2) pairwise.add(a);
        }

        foreach (var current in pairwise) {
            double weight = current.weight;
            string left = current.sets[0];
            string right = current.sets[1];
            // A fully contained circle must not be positioned early.
            if (current.size + SMALL >= double.min(find(circles, left).size, find(circles, right).size)) {
                weight = 0;
            }
            overlaps.get(left).add(new Overlap(right, current.size, weight));
            overlaps.get(right).add(new Overlap(left, current.size, weight));
        }

        // Most overlapped first (stable, like Array.prototype.sort in V8).
        var ranked = new Gee.ArrayList<Overlap>();
        foreach (string set in order) {
            double size = 0;
            foreach (var o in overlaps.get(set)) size += o.size * o.weight;
            ranked.add(new Overlap(set, size, 1.0));
        }
        stable_sort_desc(ranked);

        var positioned = new Gee.HashSet<string>();
        find(circles, ranked.get(0).set).x = 0;
        find(circles, ranked.get(0).set).y = 0;
        positioned.add(ranked.get(0).set);

        for (int i = 1; i < ranked.size; i++) {
            string set_index = ranked.get(i).set;
            var overlap = new Gee.ArrayList<Overlap>();
            foreach (var o in overlaps.get(set_index)) {
                if (positioned.contains(o.set)) overlap.add(o);
            }
            var set = find(circles, set_index);
            stable_sort_desc(overlap);
            if (overlap.size == 0) {
                // add_missing_areas guarantees a pairwise entry for every pair.
                continue;
            }

            var points = new Gee.ArrayList<VennPoint>();
            for (int j = 0; j < overlap.size; j++) {
                var p1 = find(circles, overlap.get(j).set);
                double d1 = distance_from_intersect_area(set.radius, p1.radius, overlap.get(j).size);
                points.add(new VennPoint(p1.x + d1, p1.y));
                points.add(new VennPoint(p1.x - d1, p1.y));
                points.add(new VennPoint(p1.x, p1.y + d1));
                points.add(new VennPoint(p1.x, p1.y - d1));
                for (int k = j + 1; k < overlap.size; k++) {
                    var p2 = find(circles, overlap.get(k).set);
                    double d2 = distance_from_intersect_area(set.radius, p2.radius, overlap.get(k).size);
                    foreach (var extra in circle_circle_intersection(p1.x, p1.y, d1, p2.x, p2.y, d2)) {
                        points.add(extra);
                    }
                }
            }

            double best_loss = 1e50;
            var best = points.get(0);
            foreach (var point in points) {
                set.x = point.x;
                set.y = point.y;
                double local = loss_function(circles, pairwise);
                if (local < best_loss) {
                    best_loss = local;
                    best = point;
                }
            }
            set.x = best.x;
            set.y = best.y;
            positioned.add(set_index);
        }

        return circles;
    }

    private static void stable_sort_desc(Gee.ArrayList<Overlap> list) {
        for (int i = 1; i < list.size; i++) {
            var cur = list.get(i);
            int j = i - 1;
            while (j >= 0 && list.get(j).size < cur.size) {
                list.set(j + 1, list.get(j));
                j--;
            }
            list.set(j + 1, cur);
        }
    }

    /** venn(): greedy initial layout, then a Nelder-Mead refinement on the full loss. */
    private static Gee.ArrayList<VennCircle> venn(Gee.List<VennArea> sets, int max_iterations = 500) {
        var areas = add_missing_areas(sets);
        var circles = greedy_layout(areas);

        int n = circles.size;
        double[] initial = new double[2 * n];
        for (int i = 0; i < n; i++) {
            initial[2 * i] = circles.get(i).x;
            initial[2 * i + 1] = circles.get(i).y;
        }

        var scratch = new Gee.ArrayList<VennCircle>();
        foreach (var c in circles) scratch.add(c.copy());

        double[] solution = nelder_mead((values) => {
            for (int i = 0; i < n; i++) {
                scratch.get(i).x = values[2 * i];
                scratch.get(i).y = values[2 * i + 1];
            }
            return loss_function(scratch, areas);
        }, initial, max_iterations);

        for (int i = 0; i < n; i++) {
            circles.get(i).x = solution[2 * i];
            circles.get(i).y = solution[2 * i + 1];
        }
        return circles;
    }

    /** disjointCluster: union-find over "circles that touch". */
    private static Gee.ArrayList<Gee.ArrayList<VennCircle>> disjoint_cluster(
            Gee.ArrayList<VennCircle> circles) {
        int n = circles.size;
        int[] parent = new int[n];
        for (int i = 0; i < n; i++) parent[i] = i;

        for (int i = 0; i < n; i++) {
            for (int j = i + 1; j < n; j++) {
                var a = circles.get(i);
                var b = circles.get(j);
                if (distance(a.x, a.y, b.x, b.y) + 1e-10 < a.radius + b.radius) {
                    parent[find_root(parent, j)] = find_root(parent, i);
                }
            }
        }

        var groups = new Gee.ArrayList<Gee.ArrayList<VennCircle>>();
        var by_root = new Gee.HashMap<int, Gee.ArrayList<VennCircle>>();
        for (int i = 0; i < n; i++) {
            int root = find_root(parent, i);
            if (!by_root.has_key(root)) {
                var list = new Gee.ArrayList<VennCircle>();
                by_root.set(root, list);
                groups.add(list);
            }
            by_root.get(root).add(circles.get(i));
        }
        return groups;
    }

    private static int find_root(int[] parent, int i) {
        while (parent[i] != i) {
            parent[i] = parent[parent[i]];
            i = parent[i];
        }
        return i;
    }

    /** orientateCircles: largest at the origin, second at `orientation`, third mirrored up. */
    private static void orientate_circles(Gee.ArrayList<VennCircle> circles, double orientation) {
        // b.radius - a.radius: descending radius, stably.
        for (int i = 1; i < circles.size; i++) {
            var cur = circles.get(i);
            int j = i - 1;
            while (j >= 0 && circles.get(j).radius < cur.radius) {
                circles.set(j + 1, circles.get(j));
                j--;
            }
            circles.set(j + 1, cur);
        }

        if (circles.size > 0) {
            double lx = circles.get(0).x;
            double ly = circles.get(0).y;
            foreach (var c in circles) {
                c.x -= lx;
                c.y -= ly;
            }
        }

        if (circles.size == 2) {
            var a = circles.get(0);
            var b = circles.get(1);
            // A circle fully inside another is pushed off to one side
            // (venn.js issue #120), otherwise it would sit concentric.
            if (distance(a.x, a.y, b.x, b.y) < Math.fabs(b.radius - a.radius)) {
                b.x = a.x + a.radius - b.radius - 1e-10;
                b.y = a.y;
            }
        }

        if (circles.size > 1) {
            double rotation = Math.atan2(circles.get(1).x, circles.get(1).y) - orientation;
            double c = Math.cos(rotation);
            double s = Math.sin(rotation);
            foreach (var circle in circles) {
                double x = circle.x;
                double y = circle.y;
                circle.x = c * x - s * y;
                circle.y = s * x + c * y;
            }
        }

        if (circles.size > 2) {
            double angle = Math.atan2(circles.get(2).x, circles.get(2).y) - orientation;
            while (angle < 0) angle += 2 * Math.PI;
            while (angle > 2 * Math.PI) angle -= 2 * Math.PI;
            if (angle > Math.PI) {
                double slope = circles.get(1).y / (1e-10 + circles.get(1).x);
                foreach (var circle in circles) {
                    double d = (circle.x + slope * circle.y) / (1 + slope * slope);
                    circle.x = 2 * d - circle.x;
                    circle.y = 2 * d * slope - circle.y;
                }
            }
        }
    }

    private static void bounding_box(Gee.ArrayList<VennCircle> circles,
                                     out double xmin, out double xmax,
                                     out double ymin, out double ymax) {
        xmin = double.MAX; xmax = -double.MAX;
        ymin = double.MAX; ymax = -double.MAX;
        foreach (var c in circles) {
            xmin = double.min(xmin, c.x - c.radius);
            xmax = double.max(xmax, c.x + c.radius);
            ymin = double.min(ymin, c.y - c.radius);
            ymax = double.max(ymax, c.y + c.radius);
        }
    }

    /**
     * normalizeSolution: orientate every disjoint cluster, then pack them —
     * the largest at the origin, the rest placed right / below / below-right of
     * the accumulated bounds, three per round, exactly as venn.js does.
     *
     * This used to keep only the largest cluster, on the reasoning that every
     * diagram mermaid can draw has all sets overlapping. That is false: mermaid
     * renders `set A` and `set B` with no `union` between them as two separate
     * circles. Keeping one cluster dropped the other set from the drawing and
     * left the renderer looking up a circle that was not there (a
     * `gee_abstract_collection_get_size: assertion 'self != NULL'` CRITICAL).
     */
    private static Gee.ArrayList<VennCircle> normalize_solution(Gee.ArrayList<VennCircle> solution,
                                                                double orientation) {
        var circles = new Gee.ArrayList<VennCircle>();
        foreach (var c in solution) circles.add(c.copy());

        var clusters = disjoint_cluster(circles);
        // Orientate each cluster and sort them by bounding-box area, largest first.
        var sized = new Gee.ArrayList<ClusterBounds>();
        foreach (var cluster in clusters) {
            orientate_circles(cluster, orientation);
            var cb = new ClusterBounds(cluster);
            sized.add(cb);
        }
        sized.sort((a, b) => (b.area > a.area) ? 1 : ((b.area < a.area) ? -1 : 0));

        var packed = new Gee.ArrayList<VennCircle>();
        foreach (var c in sized.get(0).circles) packed.add(c);
        double rx_min, rx_max, ry_min, ry_max;
        bounding_box(packed, out rx_min, out rx_max, out ry_min, out ry_max);
        double spacing = (rx_max - rx_min) / 50.0;

        int index = 1;
        while (index < sized.size) {
            for (int k = 0; k < 3 && index + k < sized.size; k++) {
                bool right = (k == 0 || k == 2);
                bool bottom = (k == 1 || k == 2);
                add_cluster(packed, sized.get(index + k), right, bottom, spacing,
                            rx_min, rx_max, ry_min, ry_max);
            }
            index += 3;
            bounding_box(packed, out rx_min, out rx_max, out ry_min, out ry_max);
        }
        return packed;
    }

    /** A cluster with its bounding box, for packing. */
    private class ClusterBounds : Object {
        public Gee.ArrayList<VennCircle> circles;
        public double xmin;
        public double xmax;
        public double ymin;
        public double ymax;
        public double area;
        public ClusterBounds(Gee.ArrayList<VennCircle> cluster) {
            circles = cluster;
            bounding_box(cluster, out xmin, out xmax, out ymin, out ymax);
            area = (xmax - xmin) * (ymax - ymin);
        }
    }

    /** venn.js normalizeSolution's addCluster: offset a cluster and append it. */
    private static void add_cluster(Gee.ArrayList<VennCircle> into, ClusterBounds cb,
                                    bool right, bool bottom, double spacing,
                                    double rx_min, double rx_max,
                                    double ry_min, double ry_max) {
        double x_offset, y_offset, centreing;
        if (right) {
            x_offset = rx_max - cb.xmin + spacing;
        } else {
            x_offset = rx_max - cb.xmax;
            centreing = (cb.xmax - cb.xmin) / 2 - (rx_max - rx_min) / 2;
            if (centreing < 0) x_offset += centreing;
        }
        if (bottom) {
            y_offset = ry_max - cb.ymin + spacing;
        } else {
            y_offset = ry_max - cb.ymax;
            centreing = (cb.ymax - cb.ymin) / 2 - (ry_max - ry_min) / 2;
            if (centreing < 0) y_offset += centreing;
        }
        foreach (var c in cb.circles) {
            c.x += x_offset;
            c.y += y_offset;
            into.add(c);
        }
    }

    /** scaleSolution: fit into width × height minus padding, centred. */
    private static Gee.ArrayList<VennCircle> scale_solution(Gee.ArrayList<VennCircle> solution,
                                                            double width, double height,
                                                            double padding) {
        width -= 2 * padding;
        height -= 2 * padding;

        double xmin, xmax, ymin, ymax;
        bounding_box(solution, out xmin, out xmax, out ymin, out ymax);
        if (xmax == xmin || ymax == ymin) return solution;  // zero size: leave alone

        double scaling = double.min(height / (ymax - ymin), width / (xmax - xmin));
        double xoffset = (width - (xmax - xmin) * scaling) / 2;
        double yoffset = (height - (ymax - ymin) * scaling) / 2;

        var scaled = new Gee.ArrayList<VennCircle>();
        foreach (var c in solution) {
            scaled.add(new VennCircle(c.setid,
                padding + xoffset + (c.x - xmin) * scaling,
                padding + yoffset + (c.y - ymin) * scaling,
                scaling * c.radius, c.size));
        }
        return scaled;
    }

    // ── diagram.js ───────────────────────────────────────────────

    private static double circle_margin(double x, double y,
                                        Gee.List<VennCircle> interior,
                                        Gee.List<VennCircle> exterior) {
        var i0 = interior.get(0);
        double margin = i0.radius - distance(i0.x, i0.y, x, y);
        for (int i = 1; i < interior.size; i++) {
            var c = interior.get(i);
            double m = c.radius - distance(c.x, c.y, x, y);
            if (m <= margin) margin = m;
        }
        foreach (var c in exterior) {
            double m = distance(c.x, c.y, x, y) - c.radius;
            if (m <= margin) margin = m;
        }
        return margin;
    }

    /**
     * computeTextCentre: the point of maximum margin inside `interior` and
     * outside `exterior`. x stays at -1e9 when the area is not on screen.
     */
    private static void compute_text_centre(Gee.List<VennCircle> interior,
                                            Gee.List<VennCircle> exterior,
                                            out double tx, out double ty) {
        tx = -1e9;
        ty = -1e9;
        if (interior.size == 0) return;

        var xs = new Gee.ArrayList<double?>();
        var ys = new Gee.ArrayList<double?>();
        foreach (var c in interior) {
            xs.add(c.x);              ys.add(c.y);
            xs.add(c.x + c.radius / 2); ys.add(c.y);
            xs.add(c.x - c.radius / 2); ys.add(c.y);
            xs.add(c.x);              ys.add(c.y + c.radius / 2);
            xs.add(c.x);              ys.add(c.y - c.radius / 2);
        }
        double ix = xs.get(0), iy = ys.get(0);
        double margin = circle_margin(ix, iy, interior, exterior);
        for (int i = 1; i < xs.size; i++) {
            double m = circle_margin(xs.get(i), ys.get(i), interior, exterior);
            if (m >= margin) {
                ix = xs.get(i);
                iy = ys.get(i);
                margin = m;
            }
        }

        double[] start = { ix, iy };
        double[] solution = nelder_mead(
            (p) => -1 * circle_margin(p[0], p[1], interior, exterior),
            start, 500, 1e-10);

        double rx = solution[0];
        double ry = solution[1];
        bool valid = true;
        foreach (var c in interior) {
            if (distance(rx, ry, c.x, c.y) > c.radius) { valid = false; break; }
        }
        if (valid) {
            foreach (var c in exterior) {
                if (distance(rx, ry, c.x, c.y) < c.radius) { valid = false; break; }
            }
        }
        if (valid) {
            tx = rx;
            ty = ry;
            return;
        }

        if (interior.size == 1) {
            tx = interior.get(0).x;
            ty = interior.get(0).y;
            return;
        }
        var arcs = new Gee.ArrayList<VennArc>();
        intersection_area(interior, arcs);
        if (arcs.size == 0) {
            return;  // disjoint: not represented on screen
        }
        if (arcs.size == 1) {
            tx = arcs.get(0).circle.x;
            ty = arcs.get(0).circle.y;
            return;
        }
        if (exterior.size > 0) {
            compute_text_centre(interior, new Gee.ArrayList<VennCircle>(), out tx, out ty);
            return;
        }
        double sx = 0, sy = 0;
        foreach (var a in arcs) { sx += a.p1.x; sy += a.p1.y; }
        tx = sx / arcs.size;
        ty = sy / arcs.size;
    }

    // ── public entry point ───────────────────────────────────────

    /**
     * Lays the subsets out into a `width` × `height` box with `padding` around
     * it, exactly as mermaid's venn renderer does: venn() → normalizeSolution
     * (orientation π/2) → scaleSolution → computeTextCentres.
     */
    public static VennSolution compute(Gee.List<VennArea> areas,
                                       double width, double height, double padding) {
        var result = new VennSolution();
        if (areas.size == 0) return result;

        // VennDiagram drops zero-sized sets and anything that references them.
        var dropped = new Gee.HashSet<string>();
        foreach (var a in areas) {
            if (a.size == 0 && a.sets.length == 1) dropped.add(a.sets[0]);
        }
        var data = new Gee.ArrayList<VennArea>();
        foreach (var a in areas) {
            bool keep = true;
            foreach (string s in a.sets) {
                if (dropped.contains(s)) { keep = false; break; }
            }
            if (keep) data.add(a);
        }
        if (data.size == 0) return result;

        var solution = venn(data);
        solution = normalize_solution(solution, Math.PI / 2);
        var circles = scale_solution(solution, width, height, padding);
        foreach (var c in circles) result.circles.add(c);

        // getOverlappingCircles: a circle completely inside another is excluded
        // from the exterior set when centring that other circle's label.
        var contained_in = new Gee.HashMap<string, Gee.ArrayList<string>>();
        foreach (var c in circles) contained_in.set(c.setid, new Gee.ArrayList<string>());
        for (int i = 0; i < circles.size; i++) {
            for (int j = i + 1; j < circles.size; j++) {
                var a = circles.get(i);
                var b = circles.get(j);
                double d = distance(a.x, a.y, b.x, b.y);
                if (d + b.radius <= a.radius + 1e-10) {
                    contained_in.get(b.setid).add(a.setid);
                } else if (d + a.radius <= b.radius + 1e-10) {
                    contained_in.get(a.setid).add(b.setid);
                }
            }
        }

        foreach (var area in data) {
            var member = new Gee.HashSet<string>();
            var exclude = new Gee.HashSet<string>();
            foreach (string s in area.sets) {
                member.add(s);
                foreach (string o in contained_in.get(s)) exclude.add(o);
            }
            var interior = new Gee.ArrayList<VennCircle>();
            var exterior = new Gee.ArrayList<VennCircle>();
            foreach (var c in circles) {
                if (member.contains(c.setid)) interior.add(c);
                else if (!exclude.contains(c.setid)) exterior.add(c);
            }
            double tx, ty;
            compute_text_centre(interior, exterior, out tx, out ty);
            string key = string.joinv("|", area.sets);
            result.text_x.set(key, tx);
            result.text_y.set(key, ty);
        }

        return result;
    }

    /**
     * ensurePairwiseSubsets (vennRenderer.ts): venn.js needs an explicit
     * pairwise entry for every pair inside an N-set union (N ≥ 3) to overlap
     * the circles at all. Returns a new list; the AST is never mutated.
     */
    public static Gee.ArrayList<VennArea> ensure_pairwise(Gee.List<VennArea> subsets) {
        var result = new Gee.ArrayList<VennArea>();
        result.add_all(subsets);

        var existing = new Gee.HashSet<string>();
        var single_sizes = new Gee.HashMap<string, double?>();
        foreach (var s in subsets) {
            var sorted = sorted_sets(s.sets);
            existing.add(string.joinv("|", sorted));
            if (s.sets.length == 1) single_sizes.set(s.sets[0], s.size);
        }

        foreach (var subset in subsets) {
            if (subset.sets.length < 3) continue;
            var members = sorted_sets(subset.sets);
            for (int i = 0; i < members.length - 1; i++) {
                for (int j = i + 1; j < members.length; j++) {
                    string key = members[i] + "|" + members[j];
                    if (existing.contains(key)) continue;
                    existing.add(key);
                    // 1/4 of the smaller set, or the parser's 2-set default.
                    double pair_size = 2.5;
                    if (single_sizes.has_key(members[i]) && single_sizes.has_key(members[j])) {
                        pair_size = double.min(single_sizes.get(members[i]),
                                               single_sizes.get(members[j])) / 4;
                    }
                    result.add(new VennArea({ members[i], members[j] }, pair_size));
                }
            }
        }
        return result;
    }

    private static string[] sorted_sets(string[] sets) {
        var list = new Gee.ArrayList<string>();
        foreach (string s in sets) list.add(s);
        list.sort((a, b) => strcmp(a, b));
        // Not list.to_array(): Gee's generic to_array() generates a gpointer*
        // that valac assigns straight into a gchar** (an -Wincompatible-pointer-types
        // warning the build keeps switched on).
        string[] result = new string[list.size];
        for (int i = 0; i < list.size; i++) result[i] = list.get(i);
        return result;
    }
}

}
