import re

with open('D:/geteco/game/district/bairro1/Bairro1Expansion.gd', 'r', encoding='utf-8') as f:
    text = f.read()

spots = []
for m in re.finditer(r'\{"position":\s*Vector2\(([^)]+)\),\s*"rotation":\s*([^,]+),\s*"zone":\s*"([^"]+)"\}', text):
    pos_str, rot_str, zone = m.groups()
    x, y = [float(v.strip()) for v in pos_str.split(',')]
    spots.append((x, y, rot_str.strip(), zone))

print(f'Total spots: {len(spots)}')
for i, s1 in enumerate(spots):
    for j, s2 in enumerate(spots):
        if i < j:
            dist = ((s1[0]-s2[0])**2 + (s1[1]-s2[1])**2)**0.5
            if dist < 85.0:
                print(f'CONFLICT! Spot {i} {s1[:2]} ({s1[3]}) and Spot {j} {s2[:2]} ({s2[3]}) distance = {dist:.1f}px!')
