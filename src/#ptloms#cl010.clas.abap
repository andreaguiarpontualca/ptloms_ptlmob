class /PTLOMS/CL010 definition
  public
  final
  create public .

public section.

  class-methods INSERIR
    changing
      !CH_CONTROLE type /PTLOMS/TB048 .
protected section.
private section.

  methods DELETAR .
  methods BUSCAR .
ENDCLASS.



CLASS /PTLOMS/CL010 IMPLEMENTATION.


  method BUSCAR.
  endmethod.


  method DELETAR.
  endmethod.


  METHOD inserir.

    ch_controle-data = sy-datum.
    ch_controle-hora = sy-uzeit.

    INSERT /ptloms/tb048 FROM ch_controle.

  ENDMETHOD.
ENDCLASS.
