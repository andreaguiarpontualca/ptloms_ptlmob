REPORT /ptloms/rp027.

*---------------------------------------------------------------------*
* ZFIORI_CONN_KEEPALIVE_CHECK
*
* Objetivos:
* - Testar URL HTTP/OData completa e dinâmica
* - Avaliar disponibilidade, latência, keep-alive e idle timeout
* - Manter o mesmo IF_HTTP_CLIENT entre chamadas
* - Recriar o client após falha de comunicação
* - Exibir progresso durante chamadas e intervalos
* - Limitar a duração máxima para evitar execução excessiva
*---------------------------------------------------------------------*

PARAMETERS:
  p_url    TYPE string LOWER CASE OBLIGATORY,
  p_dest   TYPE rfcdest LOWER CASE,
  p_user   TYPE string LOWER CASE,
  p_pass   TYPE string LOWER CASE,
  p_times  TYPE i DEFAULT 5,
  p_idle   TYPE i DEFAULT 5,
  p_timeo  TYPE i DEFAULT 30,
  p_maxmin TYPE i DEFAULT 15,
  p_meth   TYPE c LENGTH 4 DEFAULT 'GET',
  p_accept TYPE string LOWER CASE DEFAULT '*/*',
  p_close  AS CHECKBOX DEFAULT space,
  p_body   AS CHECKBOX DEFAULT space.

*---------------------------------------------------------------------*
* Tipos
*---------------------------------------------------------------------*
TYPES: BEGIN OF ty_result,
         seq             TYPE i,
         datum           TYPE sy-datum,
         uzeit           TYPE sy-uzeit,
         phase           TYPE c LENGTH 10,
         http_code       TYPE i,
         reason          TYPE string,
         time_total_ms   TYPE p LENGTH 16 DECIMALS 2,
         response_bytes  TYPE i,
         connection_hdr  TYPE string,
         keepalive_hdr   TYPE string,
         set_cookie_hdr  TYPE string,
         sap_session_hdr TYPE string,
         sap_error_code  TYPE i,
         sap_error_text  TYPE string,
         ok              TYPE abap_bool,
         error_text      TYPE string,
       END OF ty_result.

TYPES ty_t_result TYPE STANDARD TABLE OF ty_result
                  WITH DEFAULT KEY.

*---------------------------------------------------------------------*
* Classe local
*---------------------------------------------------------------------*
CLASS lcl_http_keepalive DEFINITION FINAL.

  PUBLIC SECTION.

    METHODS constructor
      IMPORTING
        iv_url         TYPE string
        iv_dest        TYPE rfcdest
        iv_user        TYPE string
        iv_pass        TYPE string
        iv_method      TYPE string
        iv_accept      TYPE string
        iv_timeout     TYPE i
        iv_force_close TYPE abap_bool
        iv_show_body   TYPE abap_bool.

    METHODS run
      IMPORTING
        iv_times         TYPE i
        iv_idle          TYPE i
        iv_maxmin        TYPE i
      RETURNING
        VALUE(rt_result) TYPE ty_t_result.

  PRIVATE SECTION.

    DATA:
      mv_url         TYPE string,
      mv_dest        TYPE rfcdest,
      mv_user        TYPE string,
      mv_pass        TYPE string,
      mv_method      TYPE string,
      mv_accept      TYPE string,
      mv_timeout     TYPE i,
      mv_force_close TYPE abap_bool,
      mv_show_body   TYPE abap_bool,
      mv_last_code   TYPE i,
      mv_last_text   TYPE string,
      mo_client      TYPE REF TO if_http_client.

    METHODS create_client
      RETURNING
        VALUE(rv_success) TYPE abap_bool.

    METHODS execute_once
      IMPORTING
        iv_seq           TYPE i
      RETURNING
        VALUE(rs_result) TYPE ty_result.

    METHODS read_last_error.

    METHODS close_client.

    METHODS show_progress
      IMPORTING
        iv_seq   TYPE i
        iv_total TYPE i
        iv_text  TYPE string.

ENDCLASS.

*---------------------------------------------------------------------*
* Dados globais
*---------------------------------------------------------------------*
DATA:
  gt_result TYPE ty_t_result,
  go_test   TYPE REF TO lcl_http_keepalive.

*---------------------------------------------------------------------*
* Implementação da classe
*---------------------------------------------------------------------*
CLASS lcl_http_keepalive IMPLEMENTATION.

  METHOD constructor.

    mv_url         = iv_url.
    mv_dest        = iv_dest.
    mv_user        = iv_user.
    mv_pass        = iv_pass.
    mv_method      = iv_method.
    mv_accept      = iv_accept.
    mv_timeout     = iv_timeout.
    mv_force_close = iv_force_close.
    mv_show_body   = iv_show_body.

  ENDMETHOD.

  METHOD show_progress.

    DATA:
      lv_percent TYPE i,
      lv_seq_c   TYPE string,
      lv_total_c TYPE string,
      lv_message TYPE string.

    IF sy-batch = abap_true.
      RETURN.
    ENDIF.

    IF iv_total > 0.
      lv_percent = iv_seq * 100 / iv_total.
    ELSE.
      lv_percent = 0.
    ENDIF.

    IF lv_percent > 100.
      lv_percent = 100.
    ENDIF.

    lv_seq_c   = iv_seq.
    lv_total_c = iv_total.

    CONCATENATE
      iv_text
      'Chamada'
      lv_seq_c
      'de'
      lv_total_c
    INTO lv_message
    SEPARATED BY space.

    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING
        percentage = lv_percent
        text       = lv_message
      EXCEPTIONS
        OTHERS     = 1.

  ENDMETHOD.

  METHOD create_client.

    DATA lv_subrc TYPE sy-subrc.

    rv_success = abap_false.

    CLEAR:
      mv_last_code,
      mv_last_text.

    close_client( ).

    IF mv_dest IS NOT INITIAL.

      cl_http_client=>create_by_destination(
        EXPORTING
          destination = mv_dest
        IMPORTING
          client      = mo_client
        EXCEPTIONS
          OTHERS      = 1 ).

      lv_subrc = sy-subrc.

    ELSE.

      cl_http_client=>create_by_url(
        EXPORTING
          url    = mv_url
        IMPORTING
          client = mo_client
        EXCEPTIONS
          OTHERS = 1 ).

      lv_subrc = sy-subrc.

    ENDIF.

    IF lv_subrc <> 0 OR mo_client IS NOT BOUND.

      mv_last_code = lv_subrc.

      IF mv_dest IS NOT INITIAL.
        mv_last_text =
          'Falha ao criar cliente HTTP pelo destino SM59'.
      ELSE.
        mv_last_text =
          'Falha ao criar cliente HTTP pela URL informada'.
      ENDIF.

      RETURN.

    ENDIF.

    mo_client->propertytype_logon_popup =
      mo_client->co_disabled.

    IF mv_user IS NOT INITIAL.

      mo_client->authenticate(
        username = mv_user
        password = mv_pass ).

    ENDIF.

    rv_success = abap_true.

  ENDMETHOD.

  METHOD read_last_error.

    CLEAR:
      mv_last_code,
      mv_last_text.

    IF mo_client IS NOT BOUND.
      RETURN.
    ENDIF.

    mo_client->get_last_error(
      IMPORTING
        code    = mv_last_code
        message = mv_last_text ).

  ENDMETHOD.

  METHOD run.

    DATA:
      lv_seq       TYPE i,
      lv_start     TYPE i,
      lv_now       TYPE i,
      lv_elapsed   TYPE i,
      lv_max_micro TYPE i,
      lv_text      TYPE string,
      lv_idle_c    TYPE string,
      ls_result    TYPE ty_result.

    CLEAR rt_result.

    lv_max_micro = iv_maxmin * 60 * 1000000.

    GET RUN TIME FIELD lv_start.

    DO iv_times TIMES.

      lv_seq = sy-index.

      GET RUN TIME FIELD lv_now.

      lv_elapsed = lv_now - lv_start.

      IF lv_elapsed < 0.
        lv_elapsed = 0.
      ENDIF.

      IF lv_elapsed >= lv_max_micro.
        EXIT.
      ENDIF.

      show_progress(
        iv_seq   = lv_seq
        iv_total = iv_times
        iv_text  = 'Executando' ).

      CLEAR ls_result.

      ls_result = execute_once( lv_seq ).

      APPEND ls_result TO rt_result.

      IF lv_seq < iv_times AND iv_idle > 0.

        GET RUN TIME FIELD lv_now.

        lv_elapsed = lv_now - lv_start.

        IF lv_elapsed < 0.
          lv_elapsed = 0.
        ENDIF.

        IF lv_elapsed + ( iv_idle * 1000000 )
           >= lv_max_micro.
          EXIT.
        ENDIF.

        lv_idle_c = iv_idle.

        CONCATENATE
          'Aguardando'
          lv_idle_c
          'segundos -'
        INTO lv_text
        SEPARATED BY space.

        show_progress(
          iv_seq   = lv_seq
          iv_total = iv_times
          iv_text  = lv_text ).

        WAIT UP TO iv_idle SECONDS.

      ENDIF.

    ENDDO.

    close_client( ).

    show_progress(
      iv_seq   = iv_times
      iv_total = iv_times
      iv_text  = 'Teste concluido -' ).

  ENDMETHOD.

  METHOD execute_once.

    DATA:
      lv_start   TYPE i,
      lv_end     TYPE i,
      lv_subrc   TYPE sy-subrc,
      lv_code    TYPE i,
      lv_code_c  TYPE string,
      lv_reason  TYPE string,
      lv_body    TYPE string,
      lv_len     TYPE i,
      lv_created TYPE abap_bool,
      lx_root    TYPE REF TO cx_root.

    CLEAR rs_result.

    rs_result-seq   = iv_seq.
    rs_result-datum = sy-datum.
    rs_result-uzeit = sy-uzeit.
    rs_result-ok    = abap_false.

    TRY.

*---------------------------------------------------------------------*
* Criação ou recriação do client
*---------------------------------------------------------------------*
        IF mo_client IS NOT BOUND.

          GET RUN TIME FIELD lv_start.

          lv_created = create_client( ).

          GET RUN TIME FIELD lv_end.

          IF lv_created = abap_false.

            rs_result-phase          = 'CREATE'.
            rs_result-time_total_ms  =
              ( lv_end - lv_start ) / 1000.
            rs_result-sap_error_code = mv_last_code.
            rs_result-sap_error_text = mv_last_text.
            rs_result-error_text     =
              'CREATE: falha ao criar cliente HTTP'.

            RETURN.

          ENDIF.

        ENDIF.

*---------------------------------------------------------------------*
* Preparação da requisição
*---------------------------------------------------------------------*
        mo_client->request->set_method( mv_method ).

        mo_client->request->set_header_field(
          name  = 'Accept'
          value = mv_accept ).

        mo_client->request->set_header_field(
          name  = 'Cache-Control'
          value = 'no-cache' ).

        mo_client->request->set_header_field(
          name  = 'X-ZFIORI-CONN-TEST'
          value = 'KEEPALIVE-IDLE-CHECK' ).

        IF mv_force_close = abap_true.

          mo_client->request->set_header_field(
            name  = 'Connection'
            value = 'close' ).

        ELSE.

          mo_client->request->set_header_field(
            name  = 'Connection'
            value = 'keep-alive' ).

        ENDIF.

*---------------------------------------------------------------------*
* SEND
*---------------------------------------------------------------------*
        GET RUN TIME FIELD lv_start.

        mo_client->send(
          EXPORTING
            timeout                    = mv_timeout
          EXCEPTIONS
            http_communication_failure = 1
            http_invalid_state         = 2
            http_processing_failed     = 3
            OTHERS                     = 4 ).

        lv_subrc = sy-subrc.

        IF lv_subrc <> 0.

          GET RUN TIME FIELD lv_end.

          read_last_error( ).

          rs_result-phase          = 'SEND'.
          rs_result-time_total_ms  =
            ( lv_end - lv_start ) / 1000.
          rs_result-sap_error_code = mv_last_code.
          rs_result-sap_error_text = mv_last_text.

          CASE lv_subrc.
            WHEN 1.
              rs_result-error_text =
                'SEND: HTTP_COMMUNICATION_FAILURE'.
            WHEN 2.
              rs_result-error_text =
                'SEND: HTTP_INVALID_STATE'.
            WHEN 3.
              rs_result-error_text =
                'SEND: HTTP_PROCESSING_FAILED'.
            WHEN OTHERS.
              rs_result-error_text =
                'SEND: erro HTTP nao identificado'.
          ENDCASE.

          close_client( ).
          RETURN.

        ENDIF.

*---------------------------------------------------------------------*
* RECEIVE
*---------------------------------------------------------------------*
        mo_client->receive(
          EXCEPTIONS
            http_communication_failure = 1
            http_invalid_state         = 2
            http_processing_failed     = 3
            OTHERS                     = 4 ).

        lv_subrc = sy-subrc.

        GET RUN TIME FIELD lv_end.

        IF lv_subrc <> 0.

          read_last_error( ).

          rs_result-phase          = 'RECEIVE'.
          rs_result-time_total_ms  =
            ( lv_end - lv_start ) / 1000.
          rs_result-sap_error_code = mv_last_code.
          rs_result-sap_error_text = mv_last_text.

          CASE lv_subrc.
            WHEN 1.
              rs_result-error_text =
                'RECEIVE: HTTP_COMMUNICATION_FAILURE'.
            WHEN 2.
              rs_result-error_text =
                'RECEIVE: HTTP_INVALID_STATE'.
            WHEN 3.
              rs_result-error_text =
                'RECEIVE: HTTP_PROCESSING_FAILED'.
            WHEN OTHERS.
              rs_result-error_text =
                'RECEIVE: erro HTTP nao identificado'.
          ENDCASE.

          close_client( ).
          RETURN.

        ENDIF.

*---------------------------------------------------------------------*
* Resposta HTTP recebida
*---------------------------------------------------------------------*
        mo_client->response->get_status(
          IMPORTING
            code   = lv_code
            reason = lv_reason ).

        lv_body = mo_client->response->get_cdata( ).
        lv_len  = strlen( lv_body ).

        rs_result-phase          = 'HTTP'.
        rs_result-http_code      = lv_code.
        rs_result-reason         = lv_reason.
        rs_result-time_total_ms  =
          ( lv_end - lv_start ) / 1000.
        rs_result-response_bytes = lv_len.

        rs_result-connection_hdr =
          mo_client->response->get_header_field(
            'Connection' ).

        rs_result-keepalive_hdr =
          mo_client->response->get_header_field(
            'Keep-Alive' ).

        rs_result-set_cookie_hdr =
          mo_client->response->get_header_field(
            'Set-Cookie' ).

        rs_result-sap_session_hdr =
          mo_client->response->get_header_field(
            'SAP-SessionCmd' ).

        IF lv_code >= 200 AND lv_code <= 299.

          rs_result-ok = abap_true.

        ELSE.

          rs_result-ok = abap_false.
          lv_code_c = lv_code.

          CONCATENATE
            'HTTP'
            lv_code_c
            lv_reason
          INTO rs_result-error_text
          SEPARATED BY space.

        ENDIF.

        IF mv_show_body = abap_true.

          SKIP.

          WRITE:
            / '--- BODY SEQ',
              iv_seq,
              '---'.

          WRITE / lv_body.

        ENDIF.

      CATCH cx_root INTO lx_root.

        GET RUN TIME FIELD lv_end.

        rs_result-phase         = 'ABAP'.
        rs_result-ok            = abap_false.
        rs_result-time_total_ms =
          ( lv_end - lv_start ) / 1000.
        rs_result-error_text    = lx_root->get_text( ).

        close_client( ).

    ENDTRY.

  ENDMETHOD.

  METHOD close_client.

    DATA lv_subrc TYPE sy-subrc.

    IF mo_client IS BOUND.

      mo_client->close(
        EXCEPTIONS
          http_invalid_state = 1
          OTHERS             = 2 ).

      lv_subrc = sy-subrc.

      CLEAR mo_client.

    ENDIF.

  ENDMETHOD.

ENDCLASS.

*---------------------------------------------------------------------*
* Exibição do resultado
*---------------------------------------------------------------------*
FORM print_result USING it_result TYPE ty_t_result.

  DATA:
    lv_total TYPE i,
    lv_ok    TYPE i,
    lv_fail  TYPE i,
    lv_min   TYPE p LENGTH 16 DECIMALS 2,
    lv_max   TYPE p LENGTH 16 DECIMALS 2,
    lv_avg   TYPE p LENGTH 16 DECIMALS 2,
    lv_sum   TYPE p LENGTH 16 DECIMALS 2.

  FIELD-SYMBOLS <ls_result> TYPE ty_result.

  DESCRIBE TABLE it_result LINES lv_total.

  LOOP AT it_result ASSIGNING <ls_result>.

    IF <ls_result>-ok = abap_true.
      lv_ok = lv_ok + 1.
    ELSE.
      lv_fail = lv_fail + 1.
    ENDIF.

    IF sy-tabix = 1
       OR <ls_result>-time_total_ms < lv_min.

      lv_min = <ls_result>-time_total_ms.

    ENDIF.

    IF <ls_result>-time_total_ms > lv_max.
      lv_max = <ls_result>-time_total_ms.
    ENDIF.

    lv_sum = lv_sum + <ls_result>-time_total_ms.

  ENDLOOP.

  IF lv_total > 0.
    lv_avg = lv_sum / lv_total.
  ENDIF.

  SKIP.

  WRITE / 'Resumo do teste keep-alive / idle timeout'.

  ULINE.

  WRITE:
    / 'URL:', p_url,
    / 'Destino RFC HTTP:', p_dest,
    / 'Execucoes solicitadas:', p_times,
    / 'Execucoes realizadas:', lv_total,
    / 'Idle entre chamadas:', p_idle, 'segundos',
    / 'Timeout HTTP:', p_timeo, 'segundos',
    / 'Duracao maxima:', p_maxmin, 'minutos',
    / 'Metodo:', p_meth,
    / 'Accept:', p_accept,
    / 'OK:', lv_ok,
    / 'Falhas:', lv_fail,
    / 'Latencia minima ms:', lv_min,
    / 'Latencia media  ms:', lv_avg,
    / 'Latencia maxima ms:', lv_max.

  IF lv_total < p_times.

    SKIP.

    FORMAT COLOR COL_TOTAL.

    WRITE:
      / 'ATENCAO: teste encerrado pelo limite maximo de duracao.'.

    FORMAT COLOR OFF.

  ENDIF.

  SKIP.

  WRITE / 'Detalhamento'.

  ULINE.

  FORMAT COLOR COL_HEADING.

  WRITE:
    / 'SEQ',
      7 'HORA',
      16 'FASE',
      28 'HTTP',
      35 'MS',
      49 'BYTES',
      60 'SAPCOD',
      70 'OK',
      75 'ERRO / DETALHE TECNICO'.

  FORMAT COLOR OFF.

  LOOP AT it_result ASSIGNING <ls_result>.

    IF <ls_result>-ok = abap_true.
      FORMAT COLOR COL_POSITIVE.
    ELSE.
      FORMAT COLOR COL_NEGATIVE.
    ENDIF.

    WRITE:
      / <ls_result>-seq,
        7 <ls_result>-uzeit,
        16 <ls_result>-phase,
        28 <ls_result>-http_code,
        35 <ls_result>-time_total_ms,
        49 <ls_result>-response_bytes,
        60 <ls_result>-sap_error_code,
        70 <ls_result>-ok,
        75 <ls_result>-error_text.

    FORMAT COLOR OFF.

    IF <ls_result>-sap_error_text IS NOT INITIAL.

      WRITE:
        /10 'Detalhe SAP:',
            <ls_result>-sap_error_text.

    ENDIF.

    IF <ls_result>-reason IS NOT INITIAL.

      WRITE:
        /10 'HTTP Reason:',
            <ls_result>-reason.

    ENDIF.

    IF <ls_result>-connection_hdr IS NOT INITIAL
       OR <ls_result>-keepalive_hdr IS NOT INITIAL.

      WRITE:
        /10 'Connection:',
            <ls_result>-connection_hdr,
        /10 'Keep-Alive:',
            <ls_result>-keepalive_hdr.

    ENDIF.

  ENDLOOP.

ENDFORM.

*---------------------------------------------------------------------*
* Validações
*---------------------------------------------------------------------*
AT SELECTION-SCREEN.

  DATA:
    lv_idle_tot TYPE i,
    lv_worst    TYPE i.

  IF p_url IS INITIAL AND p_dest IS INITIAL.

    MESSAGE
      'Informe a URL completa ou um destino HTTP SM59'
      TYPE 'E'.

  ENDIF.

  IF p_times <= 0.

    MESSAGE
      'Quantidade de execucoes deve ser maior que zero'
      TYPE 'E'.

  ENDIF.

  IF p_times > 1000.

    MESSAGE
      'Quantidade maxima permitida: 1000 execucoes'
      TYPE 'E'.

  ENDIF.

  IF p_idle < 0.

    MESSAGE
      'Intervalo idle nao pode ser negativo'
      TYPE 'E'.

  ENDIF.

  IF p_timeo <= 0.

    MESSAGE
      'Timeout deve ser maior que zero'
      TYPE 'E'.

  ENDIF.

  IF p_maxmin <= 0 OR p_maxmin > 30.

    MESSAGE
      'Duracao maxima deve ficar entre 1 e 30 minutos'
      TYPE 'E'.

  ENDIF.

  IF p_meth <> 'GET'
     AND p_meth <> 'HEAD'.

    MESSAGE
      'Para seguranca, utilize apenas GET ou HEAD'
      TYPE 'E'.

  ENDIF.

  lv_idle_tot = ( p_times - 1 ) * p_idle.
  lv_worst    = lv_idle_tot + ( p_times * p_timeo ).

  IF lv_worst > ( p_maxmin * 60 ).

    MESSAGE
      'O teste pode atingir o limite de duracao e ser encerrado'
      TYPE 'W'.

  ENDIF.

*---------------------------------------------------------------------*
* Execução
*---------------------------------------------------------------------*
START-OF-SELECTION.

  DATA lv_method TYPE string.

  lv_method = p_meth.

  CREATE OBJECT go_test
    EXPORTING
      iv_url         = p_url
      iv_dest        = p_dest
      iv_user        = p_user
      iv_pass        = p_pass
      iv_method      = lv_method
      iv_accept      = p_accept
      iv_timeout     = p_timeo
      iv_force_close = p_close
      iv_show_body   = p_body.

  gt_result = go_test->run(
    iv_times  = p_times
    iv_idle   = p_idle
    iv_maxmin = p_maxmin ).

  PERFORM print_result USING gt_result.
