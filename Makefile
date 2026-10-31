# CitronOS as its packages install it (T-2.1): `make install DESTDIR=…`, or
# one package's part, `make install-shell DESTDIR=…`. scripts/stage.sh says
# what each part holds; packaging/citronos/PKGBUILD calls one part per package.
# scripts/install.sh is for development: into your own account.
DESTDIR ?=
PARTS := runtime shell hyprland-config theme

.PHONY: install $(addprefix install-,$(PARTS)) build

build:
	node design/build.mjs >/dev/null
	node icons/build.mjs >/dev/null

install: $(addprefix install-,$(PARTS))

$(addprefix install-,$(PARTS)): install-%:
	@test -n "$(DESTDIR)" || { echo "make: DESTDIR is needed (a staging folder, not /)"; exit 2; }
	scripts/stage.sh $* "$(DESTDIR)"
