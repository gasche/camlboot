OBJS=interp.cmo
FLAGS=-g -package unix -package compiler-libs.common -linkpkg
OCAML=ocamlfind ocamlc
OCAMLOPT=ocamlfind ocamlopt

.PHONY: all clean format
all: interp interpopt

clean:
	for f in $(wildcard *.cm*) $(wildcard *.o); do rm $$f; done

format:
	ocamlformat --inplace interp.ml


.SUFFIXES: .mli .ml .cmi .cmo .cmx

.ml.cmx:
	$(OCAMLOPT) $(FLAGS) -c $<

.ml.cmo:
	$(OCAML) $(FLAGS) -c $<

interp: $(OBJS)
	$(OCAML) $(FLAGS) -linkpkg -o $@ $<

interpopt: $(OBJS:.cmo=.cmx)
	$(OCAMLOPT) $(FLAGS) -linkpkg -o $@ $<
