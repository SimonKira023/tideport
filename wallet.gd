# wallet.gd —— Autoload，名字：Wallet
# 管理玩家的金币
extends Node

signal money_changed(amount: int)

const START_MONEY := 500   # 开局资金（原来是 50，太紧，买东西/招伙伴都不够）

var money := START_MONEY

# 开新档：钱包回到开局资金（由 save_manager.reset_all 统一调用）
func reset_for_new_game() -> void:
	money = START_MONEY
	money_changed.emit(money)

func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)

func spend_money(amount: int) -> bool:
	if money < amount:
		return false
	money -= amount
	money_changed.emit(money)
	return true
