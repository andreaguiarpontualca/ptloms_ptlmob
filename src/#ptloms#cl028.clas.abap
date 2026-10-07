CLASS /ptloms/cl028 DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES:
      BEGIN OF ty_save_result,
        success     TYPE abap_bool,
        reason_code TYPE char30,
        message     TYPE string,
      END OF ty_save_result.

    METHODS save_generation
      IMPORTING
        is_generation    TYPE /ptloms/tb099
      RETURNING
        VALUE(rs_result) TYPE ty_save_result.

    METHODS mark_exported
      IMPORTING
        iv_license_id    TYPE sysuuid_c32
        iv_file_name     TYPE char128
      RETURNING
        VALUE(rs_result) TYPE ty_save_result.

    METHODS revoke
      IMPORTING
        iv_license_id    TYPE sysuuid_c32
        iv_reason        TYPE string
      RETURNING
        VALUE(rs_result) TYPE ty_save_result.

ENDCLASS.



CLASS /PTLOMS/CL028 IMPLEMENTATION.


  METHOD mark_exported.

    CLEAR rs_result.
    rs_result-success = abap_false.

    IF iv_license_id IS INITIAL.
      rs_result-reason_code = 'EMPTY_LICENSE_ID'.
      rs_result-message =
        'GUID da licença não informado.'.
      RETURN.
    ENDIF.

    UPDATE /ptloms/tb099
      SET status      = 'EXPORTED'
          file_name   = iv_file_name
          exported_by = sy-uname
          exported_on = sy-datum
          exported_at = sy-uzeit
      WHERE license_id = iv_license_id
        AND status     <> 'REVOKED'.

    IF sy-subrc <> 0.
      rs_result-reason_code = 'UPDATE_ERROR'.
      rs_result-message =
        'Não foi possível registrar a exportação da licença.'.
      RETURN.
    ENDIF.

    rs_result-success     = abap_true.
    rs_result-reason_code = 'SUCCESS'.
    rs_result-message     =
      'Exportação registrada com sucesso.'.

  ENDMETHOD.


  METHOD revoke.

    CLEAR rs_result.
    rs_result-success = abap_false.

    IF iv_license_id IS INITIAL.
      rs_result-reason_code = 'EMPTY_LICENSE_ID'.
      rs_result-message =
        'GUID da licença não informado.'.
      RETURN.
    ENDIF.

    IF iv_reason IS INITIAL.
      rs_result-reason_code = 'EMPTY_REVOKE_REASON'.
      rs_result-message =
        'Motivo da revogação não informado.'.
      RETURN.
    ENDIF.

    UPDATE /ptloms/tb099
      SET status        = 'REVOKED'
          active        = abap_false
          revoked_by    = sy-uname
          revoked_on    = sy-datum
          revoked_at    = sy-uzeit
          revoke_reason = iv_reason
      WHERE license_id = iv_license_id
        AND status     <> 'REVOKED'.

    IF sy-subrc <> 0.
      rs_result-reason_code = 'REVOKE_ERROR'.
      rs_result-message =
        'A licença não foi localizada ou já estava revogada.'.
      RETURN.
    ENDIF.

    rs_result-success     = abap_true.
    rs_result-reason_code = 'SUCCESS'.
    rs_result-message     =
      'Licença revogada com sucesso.'.

  ENDMETHOD.


METHOD save_generation.
*********************************************************************************************************
***  Trecho do código abaixo REVISADO em 20/07/2026 em função da incompatibilidade de versão com a SOLAR.
*********************************************************************************************************
***  INICIO - Iury Silva
*********************************************************************************************************


  DATA:
    ls_generation TYPE /ptloms/tb099,
    lv_existing_id TYPE /ptloms/tb099-license_id,
    lv_subrc        TYPE sysubrc,
    lv_subrc_text   TYPE char10.

  CLEAR rs_result.
  rs_result-success = abap_false.

  CLEAR ls_generation.
  ls_generation = is_generation.

*--------------------------------------------------------------------*
* Validar GUID da licença
*--------------------------------------------------------------------*
  IF ls_generation-license_id IS INITIAL.

    rs_result-reason_code = 'EMPTY_LICENSE_ID'.
    rs_result-message =
      'GUID da licença não informado para gravação.'.

    RETURN.

  ENDIF.

*--------------------------------------------------------------------*
* Validar cliente
*--------------------------------------------------------------------*
  IF ls_generation-customer_id IS INITIAL.

    rs_result-reason_code = 'EMPTY_CUSTOMER'.
    rs_result-message =
      'Cliente não informado para gravação da emissão.'.

    RETURN.

  ENDIF.

*--------------------------------------------------------------------*
* Validar centro
*--------------------------------------------------------------------*
  IF ls_generation-werks IS INITIAL.

    rs_result-reason_code = 'EMPTY_PLANT'.
    rs_result-message =
      'Centro não informado para gravação da emissão.'.

    RETURN.

  ENDIF.

*--------------------------------------------------------------------*
* Validar validade
*--------------------------------------------------------------------*
  IF ls_generation-valid_to IS INITIAL.

    rs_result-reason_code = 'EMPTY_VALID_TO'.
    rs_result-message =
      'Validade não informada para gravação da emissão.'.

    RETURN.

  ENDIF.

*--------------------------------------------------------------------*
* Verificar se a licença já existe
*--------------------------------------------------------------------*
  CLEAR lv_existing_id.

  SELECT SINGLE license_id
    INTO lv_existing_id
    FROM /ptloms/tb099
    WHERE license_id = ls_generation-license_id.

  IF sy-subrc = 0.

    rs_result-reason_code = 'LICENSE_ALREADY_EXISTS'.

    CONCATENATE
      'A licença'
      ls_generation-license_id
      'já está registrada.'
      INTO rs_result-message
      SEPARATED BY space.

    RETURN.

  ENDIF.

*--------------------------------------------------------------------*
* Preencher dados de controle
*--------------------------------------------------------------------*
  ls_generation-mandt        = sy-mandt.
  ls_generation-active       = abap_true.
  ls_generation-status       = 'GENERATED'.
  ls_generation-generated_by = sy-uname.
  ls_generation-generated_on = sy-datum.
  ls_generation-generated_at = sy-uzeit.

*--------------------------------------------------------------------*
* Gravar emissão
*--------------------------------------------------------------------*
  INSERT /ptloms/tb099
    FROM ls_generation.

  lv_subrc = sy-subrc.

  IF lv_subrc <> 0.

    rs_result-reason_code = 'INSERT_ERROR'.

    WRITE lv_subrc TO lv_subrc_text.
    CONDENSE lv_subrc_text NO-GAPS.

    CONCATENATE
      'Falha ao registrar emissão. SY-SUBRC='
      lv_subrc_text
      '.'
      INTO rs_result-message.

    RETURN.

  ENDIF.

*--------------------------------------------------------------------*
* Retorno de sucesso
*--------------------------------------------------------------------*
  rs_result-success     = abap_true.
  rs_result-reason_code = 'SUCCESS'.
  rs_result-message =
    'Emissão da licença registrada com sucesso.'.

ENDMETHOD.
***  METHOD save_generation.
***
***    DATA:
***      ls_generation TYPE /ptloms/tb099.
***
***    CLEAR rs_result.
***    rs_result-success = abap_false.
***
***    ls_generation = is_generation.
***
***    IF ls_generation-license_id IS INITIAL.
***      rs_result-reason_code = 'EMPTY_LICENSE_ID'.
***      rs_result-message =
***        'GUID da licença não informado para gravação.'.
***      RETURN.
***    ENDIF.
***
***    IF ls_generation-customer_id IS INITIAL.
***      rs_result-reason_code = 'EMPTY_CUSTOMER'.
***      rs_result-message =
***        'Cliente não informado para gravação da emissão.'.
***      RETURN.
***    ENDIF.
***
***    IF ls_generation-werks IS INITIAL.
***      rs_result-reason_code = 'EMPTY_PLANT'.
***      rs_result-message =
***        'Centro não informado para gravação da emissão.'.
***      RETURN.
***    ENDIF.
***
***    IF ls_generation-valid_to IS INITIAL.
***      rs_result-reason_code = 'EMPTY_VALID_TO'.
***      rs_result-message =
***        'Validade não informada para gravação da emissão.'.
***      RETURN.
***    ENDIF.
***
***    SELECT SINGLE license_id
***      FROM /ptloms/tb099
***      INTO @DATA(lv_existing_id)
***      WHERE license_id = @ls_generation-license_id.
***
***    IF sy-subrc = 0.
***      rs_result-reason_code = 'LICENSE_ALREADY_EXISTS'.
***      rs_result-message =
***        |A licença { ls_generation-license_id } já está registrada.|.
***      RETURN.
***    ENDIF.
***
***    ls_generation-mandt        = sy-mandt.
***    ls_generation-active       = abap_true.
***    ls_generation-status       = 'GENERATED'.
***    ls_generation-generated_by = sy-uname.
***    ls_generation-generated_on = sy-datum.
***    ls_generation-generated_at = sy-uzeit.
***
***    INSERT /ptloms/tb099
***      FROM ls_generation.
***
***    IF sy-subrc <> 0.
***      rs_result-reason_code = 'INSERT_ERROR'.
***      rs_result-message =
***        |Falha ao registrar emissão. SY-SUBRC={ sy-subrc }.|.
***      RETURN.
***    ENDIF.
***
***    rs_result-success     = abap_true.
***    rs_result-reason_code = 'SUCCESS'.
***    rs_result-message     =
***      'Emissão da licença registrada com sucesso.'.
***
***  ENDMETHOD.
*********************************************************************************************************
***  FIM - Iury Silva
*********************************************************************************************************
ENDCLASS.
