"""Runner signalen, versie 3 (20 okt 2026).

Gebaseerd op richtlijnen voor UI-geluiden en earcons:
- kort (meeste onder 0,6 s), snelle aanzet, eerste noot met accent, laatste noot langer;
- grondtonen tussen ongeveer 260 en 1050 Hz, hoog doorlaatfilter 120 Hz, harde pieken 2 tot 5 kHz getemperd;
- alles in C groot (consonant): stijgend = positief of sneller, dalend = rustiger, één toon = neutraal;
- elke soort melding heeft een eigen ritme (aantal noten), niet enkel een andere toonhoogte;
- lagen: FM-klank (marimba of klok) + zacht mallet-tikje + toon een octaaf lager voor body;
- korte stereogalm voor ruimte, alles op dezelfde waargenomen luidheid (ffmpeg loudnorm).
Twee klanken: W = warm (marimba), H = helder (klok)."""
import numpy as np, wave, os, sys, subprocess
from scipy.signal import butter, sosfilt, fftconvolve
SR = 44100
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
rng = np.random.default_rng(7)

def hz(n): return 440 * 2 ** ((n - 69) / 12)
N = {name: i for name, i in zip("C4 D4 E4 F4 G4 A4 B4 C5 D5 E5 F5 G5 A5 B5 C6 D6 E6".split(),
                                [60,62,64,65,67,69,71,72,74,76,77,79,81,83,84,86,88])}

def fm(f, dur, ratio, index, idecay, adecay):
    t = np.arange(int(SR*dur)) / SR
    I = index * np.exp(-t / idecay)
    y = np.sin(2*np.pi*f*t + I*np.sin(2*np.pi*f*ratio*t))
    a = np.exp(-t / adecay)
    att = int(SR*0.002); a[:att] *= np.linspace(0, 1, att)
    rel = int(SR*0.015); a[-rel:] *= np.linspace(1, 0, rel)
    return y * a

def mallet(dur=0.012):
    n = int(SR*dur); x = rng.standard_normal(n) * np.exp(-np.arange(n)/(SR*0.003))
    return sosfilt(butter(2, [500, 1800], "bandpass", fs=SR, output="sos"), x)

def voice(f, dur, kind, accent=1.0):
    if kind == "W":   # marimba: ratio 4, snel wegstervende boventoon
        y = fm(f, dur, 4.0, 1.3, 0.025, dur/3.2)
        y += 0.35 * fm(f/2, dur, 1.0, 0.0, 1, dur/3.5)          # body een octaaf lager
    else:            # klok: ratio 3.5, langer
        y = fm(f, dur, 3.5, 0.9, 0.12, dur/2.6)
        y += 0.22 * fm(f/2, dur, 1.0, 0.0, 1, dur/3)
    m = mallet(); y[:len(m)] += 0.25 * m
    return y * accent

def place(parts, tail=0.5):
    end = max(st + len(s)/SR for s, st in parts) + tail
    y = np.zeros(int(SR*end))
    for s, st in parts:
        i = int(SR*st); y[i:i+len(s)] += s
    return y

def ir(rt=0.45, seed=0):
    r = np.random.default_rng(seed); n = int(SR*rt)
    x = r.standard_normal(n) * np.exp(-np.arange(n)/(SR*rt/6.9))
    x = sosfilt(butter(2, 2800, "lowpass", fs=SR, output="sos"), x)
    x[:int(SR*0.008)] = 0                                      # kleine voorvertraging
    return x / np.abs(x).sum() * 30

IRL, IRR = ir(seed=1), ir(seed=2)

def finish(name, mono, wet=0.16):
    hp = butter(2, 120, "highpass", fs=SR, output="sos")
    tame = butter(2, 3200, "lowpass", fs=SR, output="sos")
    dry = sosfilt(tame, sosfilt(hp, mono))                     # pieken 2 tot 5 kHz zachter
    L = dry + wet*fftconvolve(dry, IRL)[:len(dry)]
    R = np.roll(dry, int(SR*0.0004)) + wet*fftconvolve(dry, IRR)[:len(dry)]
    st = np.stack([L, R], 1)
    # Zelfde luidheid: RMS over het hoorbare deel naar -14 dB, pieken begrensd op -1 dB.
    m = np.abs(st).max(1); active = st[m > m.max() * 0.03]
    st *= 10 ** (-14 / 20) / (np.sqrt((active ** 2).mean()) + 1e-9)
    peak = np.abs(st).max()
    if peak > 0.89: st *= 0.89 / peak
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((st*32767).astype(np.int16).tobytes())

def make(kind):
    v = lambda n, d, acc=1.0: voice(hz(N[n]), d, kind, acc)
    k = kind
    # Kilometer: twee noten, kwint omhoog, tweede langer (neutraal-positief)
    finish(f"{k}_km", place([(v("G4",0.35,1.0),0), (v("D5",0.7,0.85),0.14)]))
    # Aftellen: één korte noot (wordt 3x gespeeld, op 3, 2 en 1 s)
    finish(f"{k}_aftel", place([(v("G4",0.22,1.0),0)], tail=0.25), wet=0.1)
    # Snel blok: snel stijgend drieklankje, laatste lang (start!)
    finish(f"{k}_snel", place([(v("C5",0.25,1.0),0), (v("E5",0.25,0.9),0.07), (v("G5",0.25,0.9),0.14), (v("C6",0.9,1.0),0.21)]))
    # Herstel: twee dalende noten, rustig tempo, zachter
    finish(f"{k}_herstel", place([(v("E5",0.5,0.9),0), (v("C5",0.9,0.75),0.22)]))
    # Te traag: kort-kort-hoog, snel en hoger ("tik-tik-TIK"): drie korte noten, aandringend
    finish(f"{k}_sneller", place([(v("G5",0.12,1.0),0), (v("G5",0.12,0.85),0.11), (v("C6",0.3,1.0),0.22)]), wet=0.1)
    # Te snel: twee lange, lage noten die rustig dalen (E5 naar A4), zacht en traag
    finish(f"{k}_rustiger", place([(v("E5",0.7,0.85),0), (v("A4",1.1,0.75),0.38)]), wet=0.22)
    # Verschil volgens de earcon-richtlijnen: ander aantal noten, ander ritme en ander register,
    # niet enkel een andere richting.
    # Terug op tempo: één zachte toon
    finish(f"{k}_optempo", place([(v("G5",0.5,0.8),0)]))
    # Klaar: arpeggio omhoog + akkoord dat uitklinkt
    chord = v("C5",1.6,0.7) + v("E5",1.6,0.6) + v("G5",1.6,0.6)
    finish(f"{k}_klaar", place([(v("C5",0.3,1.0),0), (v("E5",0.3,0.9),0.1), (v("G5",0.3,0.9),0.2), (chord,0.3), (v("C6",1.4,0.8),0.3)], tail=0.8), wet=0.22)
    # Pauze: één lage toon. Hervat: twee korte noten omhoog
    finish(f"{k}_pauze", place([(v("C4",0.45,1.0),0)]))
    finish(f"{k}_hervat", place([(v("C4",0.22,1.0),0), (v("G4",0.4,0.9),0.09)]))

make("W"); make("H")
print("ok")
