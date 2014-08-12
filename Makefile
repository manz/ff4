AS = x816
GPP = gpp

PROJECT= ff4

all: build/$(PROJECT).ips

build/$(PROJECT).ips: build/$(PROJECT)_precomp.s
	PYTHONPATH=../src $(AS) -o build/$(PROJECT).ips build/$(PROJECT)_precomp.s

build/$(PROJECT)_precomp.s:  $(wildcard src/*.s)
					     $(GPP) ff4.s > build/$(PROJECT)_precomp.s

clean:
	rm -f build/ff4.ips build/ff4_precomp.s
