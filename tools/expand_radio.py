"""Download and normalize CC0 songs, preserving the existing audio bank."""
import hashlib
import json
import re
import urllib.request
import numpy as np
import build_living_city_audio as bank

TRACKS = {
    'porto_groove': ('wednesday-night-funk-fusion', 'wednesday_night.ogg'),
    'porto_brisa': ('apple-cider', 'apple_cider.ogg'),
    'porto_neon': ('the-way-it-is', 'the_way_it_is.mp3'),
    'porto_arcade': ('the-cool-factor', 'the_cool_factor.wav'),
    'porto_pesada': ('the-end-day-30', 'the_end_2.wav'),
}

def main():
    manifest_path = bank.OUT / 'SOURCES.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    bank.CACHE.mkdir(parents=True, exist_ok=True)
    for key, (slug, filename) in TRACKS.items():
        page = 'https://opengameart.org/content/' + slug
        html = urllib.request.urlopen(page, timeout=45).read().decode()
        assert 'creativecommons.org/publicdomain/zero' in html
        url = re.search(r'https://opengameart.org/sites/default/files/' + re.escape(filename), html).group()
        source = bank.CACHE / filename
        if not source.exists():
            source.write_bytes(urllib.request.urlopen(url, timeout=60).read())
        x = bank.normalize(bank.decode(source, True), -19, -3)
        n = int(.12 * bank.RATE)
        x[:n] *= np.linspace(0, 1, n)[:, None]
        x[-n:] *= np.linspace(1, 0, n)[:, None]
        output = bank.write(key + '.ogg', x, True)
        manifest['sources'][key] = dict(author='Zane Little Music', page=page,
            download=url, license='CC0-1.0', sha256=hashlib.sha256(source.read_bytes()).hexdigest())
        manifest['outputs'] = [o for o in manifest['outputs'] if o['file'] != output['file']]
        manifest['outputs'].append(output)
        print(output, flush=True)
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

if __name__ == '__main__':
    main()
