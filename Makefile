OUTDIR=out
PACKAGES=$(wildcard packages/*)

.PHONY: all build repo-add clean
all: build

build:
	@mkdir -p $(OUTDIR)
	@./scripts/build-all.sh

repo-add:
	@if [ -z "$(REPO)" ]; then echo "Please set REPO=/path/to/repo"; exit 1; fi
	@./scripts/repoctl-add.sh $(REPO) $(OUTDIR)/*.pkg.tar.zst

clean:
	rm -rf $(OUTDIR)
