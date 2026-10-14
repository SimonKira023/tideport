# trade_stock.gd —— 商人/集市共用的种子与基础材料基准价 (半角标点)
extends RefCounted

const SEED_STOCK := [
	{"path": "res://item/carrot_seed.tres", "price": 10},
	{"path": "res://item/seed.tres", "price": 14},
	{"path": "res://item/cabbage_seed.tres", "price": 22},
	{"path": "res://item/pumpkin_seed.tres", "price": 40},
	{"path": "res://item/beet_seed.tres", "price": 22},
	{"path": "res://item/cauliflower_seed.tres", "price": 26},
]

static func shop_stock() -> Array:
	var out: Array = seed_entries_for_shop()
	out.append_array([
		{"seed": "res://item/fishing_rod.tres", "price": 50, "locked_by": "goblin_rod"},
		{"seed": "res://item/wheat.tres", "price": 8},
	])
	return out

static func market_stock() -> Array:
	var out: Array = seed_entries_for_market()
	out.append_array([
		{"path": "res://item/wood.tres", "price": 9},
		{"path": "res://item/wood_floor.tres", "price": 12},
		{"path": "res://item/gravel_path.tres", "price": 6},
		{"path": "res://item/slab_path.tres", "price": 20},
		{"path": "res://item/brick_path.tres", "price": 26},
		{"path": "res://item/wheat.tres", "price": 8},
		{"path": "res://item/armor_wood.tres", "price": 120},
		{"path": "res://item/armor_iron.tres", "price": 300},
		{"path": "res://item/armor_gold.tres", "price": 420},
	])
	return out

static func seed_entries_for_shop() -> Array:
	var out: Array = []
	for e in SEED_STOCK:
		out.append({"seed": String(e["path"]), "price": int(e["price"])})
	return out

static func seed_entries_for_market() -> Array:
	var out: Array = []
	for e in SEED_STOCK:
		out.append({"path": String(e["path"]), "price": int(e["price"])})
	return out
