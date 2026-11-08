class_name EntitlementProvider
extends RefCounted
## Source of store-granted entitlements (future cosmetic-only purchases through the App
## Store / Google Play). The default provider owns nothing; a platform implementation can
## be dropped in via ProfileService.entitlements without touching unlock logic.

signal entitlements_changed


func owns_sku(_sku: String) -> bool:
	return false


func refresh() -> void:
	pass
