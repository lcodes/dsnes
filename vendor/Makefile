lib := ../lib

linenoise_sources := linenoise/linenoise.o
linenoise_target  := $(lib)/liblinenoise.a

nfd_target := $(lib)/libnfd.a
nfd_build  := nativefiledialog/build
nfd_make   := $(nfd_build)/gmake_macosx

all: $(linenoise_target) $(nfd_target)

$(nfd_target):
	(cd $(nfd_make) && make)
	cp $(nfd_build)/lib/Release/x64/libnfd.a $(lib)

$(linenoise_target): $(linenoise_sources)
	ar -rcs $(linenoise_target) $(linenoise_sources)

.c.o:
	$(CC) -I linenoise $(CFLAGS) -c -o $@ $<

clean:
	rm -f $(linenoise_sources) $(linenoise_target) $(nfd_target)
	(cd $(nfd_make) && make clean)
