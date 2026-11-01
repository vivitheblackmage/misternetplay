# NetPong: make -> netpong.nes (24592 bytes: 16 header + 16 KB PRG + 8 KB CHR)
EXPECTED := 24592

netpong.nes: netpong.s netpong.chr nes.cfg
	ca65 -o netpong.o netpong.s
	ld65 -C nes.cfg -o $@ netpong.o
	@size=$$(stat -c %s $@); [ $$size -eq $(EXPECTED) ] || { echo "size $$size, expected $(EXPECTED)"; exit 1; }
	@echo "OK $@ $(EXPECTED) bytes, md5 $$(md5sum $@ | cut -c1-32)"

netpong.chr: gen_chr.py
	python3 -I gen_chr.py $@

clean:
	rm -f netpong.o netpong.nes netpong.chr

.PHONY: clean
