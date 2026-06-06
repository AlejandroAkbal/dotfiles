.PHONY: mac mac-dry-run

mac:
	@bash macos/scripts/bootstrap.sh

mac-dry-run:
	@bash macos/scripts/bootstrap.sh --dry-run
