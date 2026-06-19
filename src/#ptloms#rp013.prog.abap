REPORT /ptloms/rp013.

PARAMETERS:
  p_app  TYPE /ptloms/tb083-aplicacao OBLIGATORY,
  p_cen  TYPE /ptloms/tb083-cenario OBLIGATORY,
  p_tipo TYPE /ptloms/tb083-tipo_prompt OBLIGATORY,
  p_seq  TYPE /ptloms/tb083-sequencia DEFAULT '0010',
  p_ver  TYPE /ptloms/tb083-versao DEFAULT '0001',
  p_act  TYPE /ptloms/tb083-active AS CHECKBOX DEFAULT 'X',
  p_file TYPE rlgrap-filename.

PARAMETERS:
  p_save RADIOBUTTON GROUP ac DEFAULT 'X',
  p_show RADIOBUTTON GROUP ac,
  p_del  RADIOBUTTON GROUP ac.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.

  DATA:
    lt_filetable TYPE filetable,
    lv_rc        TYPE i.

  cl_gui_frontend_services=>file_open_dialog(
    EXPORTING
      window_title      = 'Selecione o arquivo TXT do prompt'
      default_extension = 'txt'
      file_filter       = 'Texto (*.txt)|*.txt|Todos (*.*)|*.*'
    CHANGING
      file_table        = lt_filetable
      rc                = lv_rc
    EXCEPTIONS
      OTHERS            = 1 ).

  IF sy-subrc = 0 AND lv_rc > 0.
    READ TABLE lt_filetable INDEX 1 INTO DATA(ls_file).
    IF sy-subrc = 0.
      p_file = ls_file-filename.
    ENDIF.
  ENDIF.

START-OF-SELECTION.

  DATA:
    ls_cfg       TYPE /ptloms/tb083,
    ls_old       TYPE /ptloms/tb083,
    lv_prompt    TYPE string,
    lt_lines     TYPE STANDARD TABLE OF string,
    lv_file      TYPE string,
    lv_timestamp TYPE timestampl,
    lv_exists    TYPE abap_bool.

  GET TIME STAMP FIELD lv_timestamp.

*--------------------------------------------------------------------*
* EXIBIR
*--------------------------------------------------------------------*
  IF p_show = abap_true.

    SELECT SINGLE *
      FROM /ptloms/tb083
      INTO @ls_cfg
      WHERE aplicacao   = @p_app
        AND cenario     = @p_cen
        AND tipo_prompt = @p_tipo
        AND sequencia   = @p_seq
        AND versao      = @p_ver.

    IF sy-subrc <> 0.
      WRITE: / 'Prompt não encontrado.'.
      RETURN.
    ENDIF.

    FORMAT COLOR COL_HEADING.
    WRITE: / 'PROMPT IA'.
    FORMAT RESET.
    ULINE.

    WRITE: / 'Aplicação....:', ls_cfg-aplicacao.
    WRITE: / 'Cenário......:', ls_cfg-cenario.
    WRITE: / 'Tipo Prompt..:', ls_cfg-tipo_prompt.
    WRITE: / 'Sequência....:', ls_cfg-sequencia.
    WRITE: / 'Versão.......:', ls_cfg-versao.
    WRITE: / 'Ativo........:', ls_cfg-active.
    WRITE: / 'Criado por...:', ls_cfg-created_by.
    WRITE: / 'Criado em....:', ls_cfg-created_at.
    WRITE: / 'Alterado por.:', ls_cfg-changed_by.
    WRITE: / 'Alterado em..:', ls_cfg-changed_at.

    ULINE.
    WRITE: / 'PROMPT:'.
    ULINE.
    WRITE: / ls_cfg-prompt.

    RETURN.

  ENDIF.

*--------------------------------------------------------------------*
* EXCLUIR
*--------------------------------------------------------------------*
  IF p_del = abap_true.

    DELETE FROM /ptloms/tb083
      WHERE aplicacao   = @p_app
        AND cenario     = @p_cen
        AND tipo_prompt = @p_tipo
        AND sequencia   = @p_seq
        AND versao      = @p_ver.

    IF sy-subrc = 0.
      COMMIT WORK.

      WRITE: / 'Prompt excluído com sucesso.'.
      WRITE: / 'Aplicação..:', p_app.
      WRITE: / 'Cenário....:', p_cen.
      WRITE: / 'Tipo.......:', p_tipo.
      WRITE: / 'Sequência..:', p_seq.
      WRITE: / 'Versão.....:', p_ver.
    ELSE.
      ROLLBACK WORK.
      WRITE: / 'Prompt não encontrado para exclusão.'.
    ENDIF.

    RETURN.

  ENDIF.

*--------------------------------------------------------------------*
* SALVAR
*--------------------------------------------------------------------*
  IF p_save = abap_true.

    SELECT SINGLE *
      FROM /ptloms/tb083
      INTO @ls_old
      WHERE aplicacao   = @p_app
        AND cenario     = @p_cen
        AND tipo_prompt = @p_tipo
        AND sequencia   = @p_seq
        AND versao      = @p_ver.

    lv_exists = xsdbool( sy-subrc = 0 ).

*------------------------------------------------------------------*
* Carrega TXT em UTF-8
*------------------------------------------------------------------*
    IF p_file IS NOT INITIAL.

      lv_file = p_file.

      CLEAR lt_lines.

      cl_gui_frontend_services=>gui_upload(
        EXPORTING
          filename                = lv_file
          filetype                = 'ASC'
          has_field_separator     = abap_false
          codepage                = '4110'
        CHANGING
          data_tab                = lt_lines
        EXCEPTIONS
          file_open_error         = 1
          file_read_error         = 2
          no_batch                = 3
          gui_refuse_filetransfer = 4
          invalid_type            = 5
          no_authority            = 6
          unknown_error           = 7
          bad_data_format         = 8
          header_not_allowed      = 9
          separator_not_allowed   = 10
          header_too_long         = 11
          unknown_dp_error        = 12
          access_denied           = 13
          dp_out_of_memory        = 14
          disk_full               = 15
          dp_timeout              = 16
          OTHERS                  = 17 ).

      IF sy-subrc <> 0.
        WRITE: / 'Erro ao carregar arquivo:'.
        WRITE: / p_file.
        WRITE: / 'Verifique se o arquivo está salvo como UTF-8.'.
        RETURN.
      ENDIF.

      CONCATENATE LINES OF lt_lines
             INTO lv_prompt
       SEPARATED BY cl_abap_char_utilities=>newline.

      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf
        IN lv_prompt WITH cl_abap_char_utilities=>newline.

      REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab
        IN lv_prompt WITH space.

      " Remove BOM UTF-8 se existir no início do arquivo
      IF strlen( lv_prompt ) >= 1 AND lv_prompt(1) = cl_abap_char_utilities=>byte_order_mark_utf8.
        SHIFT lv_prompt LEFT BY 1 PLACES.
      ENDIF.

*------------------------------------------------------------------*
* Mantém prompt anterior se não informar TXT
*------------------------------------------------------------------*
    ELSEIF lv_exists = abap_true.

      lv_prompt = ls_old-prompt.

    ENDIF.

    IF lv_prompt IS INITIAL.
      WRITE: / 'Prompt não informado.'.
      WRITE: / 'Selecione um arquivo TXT ou mantenha um registro existente.'.
      RETURN.
    ENDIF.

*------------------------------------------------------------------*
* Monta registro
*------------------------------------------------------------------*
    CLEAR ls_cfg.

    ls_cfg-aplicacao   = p_app.
    ls_cfg-cenario     = p_cen.
    ls_cfg-tipo_prompt = p_tipo.
    ls_cfg-sequencia   = p_seq.
    ls_cfg-versao      = p_ver.
    ls_cfg-active      = p_act.
    ls_cfg-prompt      = lv_prompt.

    ls_cfg-changed_by = sy-uname.
    ls_cfg-changed_at = lv_timestamp.

*------------------------------------------------------------------*
* Auditoria
*------------------------------------------------------------------*
    IF lv_exists = abap_true.
      ls_cfg-created_by = ls_old-created_by.
      ls_cfg-created_at = ls_old-created_at.
    ELSE.
      ls_cfg-created_by = sy-uname.
      ls_cfg-created_at = lv_timestamp.
    ENDIF.

*------------------------------------------------------------------*
* Persistência
*------------------------------------------------------------------*
    MODIFY /ptloms/tb083 FROM ls_cfg.

    IF sy-subrc = 0.
      COMMIT WORK.

      WRITE: / 'Prompt gravado com sucesso.'.
      ULINE.
      WRITE: / 'Aplicação..:', p_app.
      WRITE: / 'Cenário....:', p_cen.
      WRITE: / 'Tipo.......:', p_tipo.
      WRITE: / 'Sequência..:', p_seq.
      WRITE: / 'Versão.....:', p_ver.
      WRITE: / 'Ativo......:', p_act.
    ELSE.
      ROLLBACK WORK.
      WRITE: / 'Erro ao gravar prompt.'.
    ENDIF.

  ENDIF.
