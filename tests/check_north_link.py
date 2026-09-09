import math

# Check if Catmull-Rom curve hits any lots
def catmull_rom(control, subdivisions=8):
    sampled = []
    for i in range(len(control) - 1):
        p0 = control[max(0, i - 1)]
        p1 = control[i]
        p2 = control[i + 1]
        p3 = control[min(len(control) - 1, i + 2)]
        for step in range(subdivisions):
            t = step / subdivisions
            t2 = t * t
            t3 = t2 * t
            x = 0.5 * ((2.0 * p1[0]) + (-p0[0] + p2[0]) * t + (2.0 * p0[0] - 5.0 * p1[0] + 4.0 * p2[0] - p3[0]) * t2 + (-p0[0] + 3.0 * p1[0] - 3.0 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2.0 * p1[1]) + (-p0[1] + p2[1]) * t + (2.0 * p0[1] - 5.0 * p1[1] + 4.0 * p2[1] - p3[1]) * t2 + (-p0[1] + 3.0 * p1[1] - 3.0 * p2[1] + p3[1]) * t3)
            sampled.append((x, y))
    sampled.append(control[-1])
    return sampled

def dist_pt_seg(p, a, b):
    px, py = p
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    l2 = dx*dx + dy*dy
    if l2 == 0:
        return math.hypot(px - ax, py - ay)
    t = max(0, min(1, ((px - ax)*dx + (py - ay)*dy) / l2))
    return math.hypot(px - (ax + t*dx), py - (ay + t*dy))

def rect_hits_road(rect, points, clearance):
    rx, ry, rw, rh = rect
    # check 4 corners
    corners = [(rx, ry), (rx+rw, ry), (rx+rw, ry+rh), (rx, ry+rh)]
    for i in range(len(points) - 1):
        # sample middle of segment
        p = points[i]
        # check distance from rect
        cx = max(rx, min(p[0], rx + rw))
        cy = max(ry, min(p[1], ry + rh))
        if math.hypot(p[0] - cx, p[1] - cy) <= clearance:
            return True
    return False

# Lots
police_precinct = (1060, 1338, 226, 160)
brownstone = (1310, 1340, 224, 160)
clearance = 164.0 * 0.5 + 5.0 # 87.0

# Current control:
c_curr = [(870, 1260), (1120, 1204), (1460, 1206), (1780, 1260)]
pts_curr = catmull_rom(c_curr)
print("Current hits precinct?", rect_hits_road(police_precinct, pts_curr, clearance))
print("Current first tangent:", (pts_curr[1][0] - pts_curr[0][0], pts_curr[1][1] - pts_curr[0][1]))

# Proposed control:
c_prop = [(870, 1260), (980, 1260), (1160, 1215), (1460, 1210), (1780, 1260)]
pts_prop = catmull_rom(c_prop)
print("Proposed hits precinct?", rect_hits_road(police_precinct, pts_prop, clearance))
print("Proposed hits brownstone?", rect_hits_road(brownstone, pts_prop, clearance))
print("Proposed first tangent:", (pts_prop[1][0] - pts_prop[0][0], pts_prop[1][1] - pts_prop[0][1]))
