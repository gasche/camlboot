OBJS=conf.cmo data.cmo envir.cmo \
	runtime_lib.cmo runtime_base.cmo \
	eval.cmo \
	runtime_stdlib.cmo runtime_compiler.cmo \
	primitives.cmo \
	interp.cmo
SRCS=$(OBJS:.cmo=.ml)
FLAGS=-g -package unix -package compiler-libs.common -linkpkg
OCAML=ocamlfind ocamlc
OCAMLOPT=ocamlfind ocamlopt

.PHONY: all clean format
all: interp interpopt

clean:
	for f in $(wildcard *.cm*) $(wildcard *.o); do rm $$f; done

format:
	ocamlformat --inplace $(SRCS)


.SUFFIXES: .mli .ml .cmi .cmo .cmx

.ml.cmx:
	$(OCAMLOPT) $(FLAGS) -c $<

.ml.cmo:
	$(OCAML) $(FLAGS) -c $<

.depend: $(SRCS)
	ocamldep $(SRCS) > .depend

include .depend

interp: $(OBJS)
	echo $(OCAML) $(FLAGS) -linkpkg -o $@ $+
	$(OCAML) $(FLAGS) -linkpkg -o $@ $+

interpopt: $(OBJS:.cmo=.cmx)
	$(OCAMLOPT) $(FLAGS) -linkpkg -o $@ $+

.PHONY: run

run: interpopt
# we defined a symbolic link ./ocaml-src to point to the compiler sources,
# at a version copmatible with the OCAMLINTERP_STDLIB_PATH version.
	env \
	  OCAMLRUNPARAM=b \
	  OCAMLINTERP_DEBUG=true \
	  OCAMLINTERP_STDLIB_PATH=$(shell ocamlc -where) \
	  OCAMLINTERP_SRC_PATH=./ocaml-src \
	  ./interpopt
