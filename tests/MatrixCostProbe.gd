extends RefCounted
static var totals = {}
static var peaks = {}
static var calls = {}
static func record(label: String, us: int):
 totals[label] = int(totals.get(label,0))+us
 peaks[label] = maxi(int(peaks.get(label,0)),us)
 calls[label] = int(calls.get(label,0))+1
static func take():
 var result = {"us":totals,"peak_us":peaks,"calls":calls}
 totals = {}; peaks = {}; calls = {}
 return result
