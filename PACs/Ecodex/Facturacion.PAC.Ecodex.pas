{ ******************************************************* }
{ }
{ TFacturaElectronica }
{ }
{ Copyright (C) 2017 Bambu Code SA de CV }
{ }
{ ******************************************************* }

unit Facturacion.PAC.Ecodex;

interface

uses Facturacion.ProveedorAutorizadoCertificacion,
  Facturacion.Comprobante,
  EcodexWsComun,
  EcodexWsTimbrado,
  EcodexWsClientes,
  EcodexWsCancelacion,
  PAC.Ecodex.ManejadorDeSesion,
  System.Generics.Collections,
  System.SysUtils;

type

  TProveedorEcodex = class(TInterfacedObject, IProveedorAutorizadoCertificacion)
  private
    fCredencialesPAC: TFacturacionCredencialesPAC;
    fDominioWebService: string;
    fManejadorDeSesion: TEcodexManejadorDeSesion;
    fwsClientesEcodex: IEcodexServicioClientes;
    fwsTimbradoEcodex: IEcodexServicioTimbrado;
    fwsCancelacionEcodex: IEcodexServicioCancelacion;
    function ExtraerNodoTimbre(const aComprobanteXML: TEcodexComprobanteXML)
      : TCadenaUTF8;
    procedure ProcesarExcepcionDePAC(const aExcepcion: Exception);
  public
    procedure Configurar(const aDominioWebService: string;
      const aCredencialesPAC: TFacturacionCredencialesPAC;
      const aTransaccionInicial: Int64);
    function ObtenerSaldoTimbresDeCliente(const aRFC: String): Integer;
    function CancelarDocumento(const aUUID: TCadenaUTF8): Boolean;
    function CancelarDocumentos(const aUUIDS: TListadoUUID):
        TListadoCancelacionUUID;
    function TimbrarDocumento(const aComprobante: IComprobanteFiscal;
      const aTransaccion: Int64): TCadenaUTF8;
    function ObtenerAcuseDeCancelacion(const aUUID: string): string;
  end;

const
  _LONGITUD_UUID = 36;

implementation

uses Classes,
  xmldom,
  Facturacion.Tipos,
  Soap.XSBuiltIns,
  XMLIntf,
{$IFDEF CODESITE}
  CodeSiteLogging,
{$ENDIF}
  System.RegularExpressions,
{$IF Compilerversion >= 20}
  Xml.Win.Msxmldom,
{$ELSE}
  Msxmldom,
{$IFEND}
  XMLDoc;

{ TProveedorEcodex }

procedure TProveedorEcodex.Configurar(const aDominioWebService: string;
  const aCredencialesPAC: TFacturacionCredencialesPAC;
  const aTransaccionInicial: Int64);
begin
  fDominioWebService := aDominioWebService;
  fCredencialesPAC := aCredencialesPAC;

  fManejadorDeSesion := TEcodexManejadorDeSesion.Create(fDominioWebService,
    aTransaccionInicial);
  fManejadorDeSesion.AsignarCredenciales(fCredencialesPAC);

  // Incializamos las instancias de los WebServices
  fwsTimbradoEcodex := GetWsEcodexTimbrado(False, fDominioWebService +
    '/ServicioTimbrado.svc');
  fwsClientesEcodex := GetWsEcodexClientes(False, fDominioWebService +
    '/ServicioClientes.svc');
  fwsCancelacionEcodex := GetWsEcodexCancelacion(False, fDominioWebService +
    '/ServicioCancelacion.svc');
end;

function TProveedorEcodex.ExtraerNodoTimbre(const aComprobanteXML
  : TEcodexComprobanteXML): TCadenaUTF8;
var
  contenidoComprobanteXML: TCadenaUTF8;
const
  _REGEX_TIMBRE = '<tfd:TimbreFiscalDigital.*?/>';
begin
  Assert(aComprobanteXML <> nil,
    'La respuesta del servicio de timbrado fue nula');
{$IF Compilerversion >= 20}
  // Delphi 2010 y superiores
  contenidoComprobanteXML := aComprobanteXML.DatosXML;
{$ELSE}
  contenidoComprobanteXML := UTF8Encode(aComprobanteXML.DatosXML);
{$IFEND}
  Result := TRegEx.Match(contenidoComprobanteXML, _REGEX_TIMBRE).Value;
  Assert(Result <> '', 'El XML del timbre estuvo vacio');
end;

function TProveedorEcodex.ObtenerSaldoTimbresDeCliente
  (const aRFC: String): Integer;
var
  solicitudEdoCuenta: TEcodexSolicitudEstatusCuenta;
  respuestaEdoCuenta: TEcodexRespuestaEstatusCuenta;
  tokenDeUsuario: string;
  I: Integer;
begin
  Assert(Trim(aRFC) <> '', 'El RFC para la solicitud de saldo fue vacio');
  Assert(fManejadorDeSesion <> nil,
    'La instancia fManejadorDeSesion no debio ser nula');
  Assert(fwsClientesEcodex <> nil,
    'La instancia fwsClientesEcodex no debio ser nula');

  Result := 0;

  // 1. Creamos la solicitud del edo de cuenta
  solicitudEdoCuenta := TEcodexSolicitudEstatusCuenta.Create;

  // 2. Iniciamos una nueva sesion solicitando un nuevo token
  tokenDeUsuario := fManejadorDeSesion.ObtenerNuevoTokenDeUsuario;

  try
    solicitudEdoCuenta.RFC := aRFC;
    solicitudEdoCuenta.Token := tokenDeUsuario;
    solicitudEdoCuenta.TransaccionID := fManejadorDeSesion.NumeroDeTransaccion;

    try
      respuestaEdoCuenta := fwsClientesEcodex.EstatusCuenta(solicitudEdoCuenta);
{$IFDEF CODESITE}
      CodeSite.Send('Codigo', respuestaEdoCuenta.Estatus.Codigo);
      CodeSite.Send('Descripcion', respuestaEdoCuenta.Estatus.Descripcion);
      CodeSite.Send('Fecha de Inicio', respuestaEdoCuenta.Estatus.FechaInicio);
      CodeSite.Send('Fecha de fin', respuestaEdoCuenta.Estatus.FechaFin);
      CodeSite.Send('Timbres asignados',
        respuestaEdoCuenta.Estatus.TimbresAsignados);
      CodeSite.Send('Timbres disponibles',
        respuestaEdoCuenta.Estatus.TimbresDisponibles);
      CodeSite.Send('Num certificados cargados',
        Length(respuestaEdoCuenta.Estatus.Certificados));
      // Mostramos los certificados cargados
      for I := 0 to Length(respuestaEdoCuenta.Estatus.Certificados) - 1 do
      begin
        CodeSite.Send('Certificado cargado Num. ' + IntToStr(I),
          respuestaEdoCuenta.Estatus.Certificados[I]);
      end;
{$ENDIF}
      // 3. Regresamos los timbres disponibles y no los asignados
      Result := respuestaEdoCuenta.Estatus.TimbresDisponibles;
    except
      On E: Exception do
        if Not(E Is EPACException) then
          ProcesarExcepcionDePAC(E)
        else
          raise;
    end;
  finally
    // fUltimoXMLEnviado := GetUltimoXMLEnviadoEcodexWsClientes;
    // fUltimoXMLRecibido := GetUltimoXMLRecibidoEcodexWsClientes;
    solicitudEdoCuenta.Free;
  end;
end;

procedure TProveedorEcodex.ProcesarExcepcionDePAC(const aExcepcion: Exception);
var
  mensajeExcepcion: string;
  numeroErrorSAT: Integer;
begin
  mensajeExcepcion := aExcepcion.Message;

  if (aExcepcion Is EEcodexFallaValidacionException) Or
    (aExcepcion Is EEcodexFallaServicioException) Or
    (aExcepcion is EEcodexFallaSesionException) then
  begin
    if (aExcepcion Is EEcodexFallaValidacionException) then
    begin
      mensajeExcepcion := EEcodexFallaValidacionException(aExcepcion)
        .Descripcion;

      numeroErrorSAT := EEcodexFallaValidacionException(aExcepcion).Numero;

      case numeroErrorSAT of
        // Errores t�cnicos donde la librer�a no creo bien el XML
        33101, 33102, 33105, 33106, 33111, 33116, 33126, 33127, 33128,
          33139, 33143, 33150:
          raise ESATErrorTecnicoXMLException.Create(mensajeExcepcion,
            numeroErrorSAT, False);

        // Algun valor que deb�a venir de un cat�logo no fue correcto
        33104, 33112, 33120, 33121, 33125, 33130, 33136, 33140, 33142, 33145,
          33155, 33156, 33164, 33165, 33172, 33185:
          raise ESATValorNoEnCatalogoException.Create(mensajeExcepcion,
            numeroErrorSAT, False);

        // Problema donde los datos del emisor no son correctos
        33131:
          raise ESATDatoEmisorIncorrectoException.Create(mensajeExcepcion,
            numeroErrorSAT, False);

        // Problema donde los datos del receptor no son correctos
        33132, 33133, 33134, 33135:
          raise ESATDatoReceptorIncorrectoException.Create(mensajeExcepcion,
            numeroErrorSAT, False);

        // Errores de validacion, reglas de negocio, etc.
        33107, 33108, 33109, 33110, 33113, 33114, 33115, 33118, 33122, 33123,
          33124, 33137, 33138, 33141, 33144, 33147, 33149, 33152, 33154,
          33157, 33158, 33159, 33161, 33166, 33167, 33169, 33170, 33171, 33174,
          33176, 33177, 33178, 33103, 33179, 33180, 33181, 33182, 33183, 33184,
          33186, 33187, 33189, 33190, 33192, 33193, 33195:
          raise ESATProblemaDeLlenadoException.Create(mensajeExcepcion,
            numeroErrorSAT, False);

        33196:
          raise ESATNoIdentificadoException.Create(mensajeExcepcion,
            numeroErrorSAT, False);
      else
        raise ESATErrorGenericoException.Create('EFallaValidacionException (' +
          IntToStr(EEcodexFallaValidacionException(aExcepcion).Numero) + ') ' +
          mensajeExcepcion, numeroErrorSAT, False);
      end;
    end;

    if (aExcepcion Is EEcodexFallaServicioException) then
    begin
      case EEcodexFallaServicioException(aExcepcion).Numero of
        29: raise EPACCancelacionFallidaCertificadoNoCargadoException.Create(EEcodexFallaServicioException(aExcepcion).Descripcion,
                                                                             0,
                                                                             EEcodexFallaServicioException(aExcepcion).Numero,
                                                                             False);  // NO es reintentable
      end;

      mensajeExcepcion := 'EFallaServicioException (' +
        IntToStr(EEcodexFallaServicioException(aExcepcion).Numero) + ') ' +
        EEcodexFallaServicioException(aExcepcion).Descripcion;
    end;

    if (aExcepcion Is EEcodexFallaSesionException) then
    begin
      mensajeExcepcion := 'EEcodexFallaSesionException (' +
        IntToStr(EEcodexFallaSesionException(aExcepcion).Estatus) + ') ' +
        EEcodexFallaSesionException(aExcepcion).Descripcion;
    end;

    // Si llegamos aqui y no se ha lanzado ningun otro error lanzamos el error gen�rico de PAC
    // con la propiedad reintentable en verdadero para que el cliente pueda re-intentar el proceso anterior
    raise EPACErrorGenericoException.Create(mensajeExcepcion, 0, 0, True);
  end;
end;

function TProveedorEcodex.TimbrarDocumento(const aComprobante
  : IComprobanteFiscal; const aTransaccion: Int64): TCadenaUTF8;
var
  solicitudTimbrado: TSolicitudTimbradoEcodex;
  respuestaTimbrado: TEcodexRespuestaTimbrado;
  tokenDeUsuario: string;
  mensajeFalla: string;
begin
  if fwsTimbradoEcodex = nil then
    raise EPACNoConfiguradoException.Create
      ('No se ha configurado el PAC, favor de configurar con metodo Configurar');

  // 1. Creamos la solicitud de timbrado
  solicitudTimbrado := TSolicitudTimbradoEcodex.Create;

  try
    // 2. Iniciamos una nueva sesion solicitando un nuevo token
    tokenDeUsuario := fManejadorDeSesion.ObtenerNuevoTokenDeUsuario();

    // 3. Asignamos el documento XML
    solicitudTimbrado.ComprobanteXML          := TEcodexComprobanteXML.Create;
    solicitudTimbrado.ComprobanteXML.DatosXML := aComprobante.Xml;
    solicitudTimbrado.RFC                     := fCredencialesPAC.RFC;
    solicitudTimbrado.Token                   := tokenDeUsuario;
    solicitudTimbrado.TransaccionID           := aTransaccion;

    try
      mensajeFalla := '';

      // 4. Realizamos la solicitud de timbrado
      respuestaTimbrado := fwsTimbradoEcodex.TimbraXML(solicitudTimbrado);

      Result := ExtraerNodoTimbre(respuestaTimbrado.ComprobanteXML);
      respuestaTimbrado.Free;
    except
      On E: Exception do
        ProcesarExcepcionDePAC(E);
    end;
  finally
    if Assigned(solicitudTimbrado) then
      solicitudTimbrado.Free;
  end;

end;

function TProveedorEcodex.CancelarDocumento(const aUUID: TCadenaUTF8): Boolean;
var
  arregloUUIDs: TListadoUUID;
  resultadoCancelacion : TListadoCancelacionUUID;
  solicitudCancelacion: TEcodexSolicitudCancelacion;
  respuestaCancelacion: TEcodexRespuestaCancelacion;
  tokenDeUsuario : String;
begin
  Assert(Length(aUUID) = _LONGITUD_UUID, 'La longitud del UUID debio de ser de ' + IntToStr(_LONGITUD_UUID));
  tokenDeUsuario                     := fManejadorDeSesion.ObtenerNuevoTokenDeUsuario();

  solicitudCancelacion               := TEcodexSolicitudCancelacion.Create;
  try
    solicitudCancelacion.RFC           := fCredencialesPAC.RFC;
    solicitudCancelacion.Token         := tokenDeUsuario;
    solicitudCancelacion.TransaccionID := fManejadorDeSesion.NumeroDeTransaccion;
    solicitudCancelacion.UUID          := aUUID;

    try
      respuestaCancelacion := fwsTimbradoEcodex.CancelaTimbrado(solicitudCancelacion);
      Result := respuestaCancelacion.Cancelada;
      respuestaCancelacion.Free;
    except
      On E: Exception do
        ProcesarExcepcionDePAC(E);
    end;
  finally
    solicitudCancelacion.Free;
  end;
end;

function TProveedorEcodex.ObtenerAcuseDeCancelacion(const aUUID: string):
    string;
var
  tokenDeUsuario: String;
  solicitudAcuse : TEcodexSolicitudAcuse;
  respuestaAcuse : TEcodexRespuestaRecuperarAcuse;
begin
  Assert(Length(aUUID) = _LONGITUD_UUID, 'La longitud del UUID debio de ser de ' + IntToStr(_LONGITUD_UUID));
  Result := '';

  // 1. Creamos la solicitud de cancelacion
  solicitudAcuse := TEcodexSolicitudAcuse.Create;

  // 2. Iniciamos una nueva sesion solicitando un nuevo token
  tokenDeUsuario := fManejadorDeSesion.ObtenerNuevoTokenDeUsuario;

  try
    try
      solicitudAcuse.UUID          := aUUID;
      solicitudAcuse.RFC           := fCredencialesPAC.RFC;
      solicitudAcuse.Token         := tokenDeUsuario;
      solicitudAcuse.TransaccionID := fManejadorDeSesion.NumeroDeTransaccion;

      respuestaAcuse := fwsCancelacionEcodex.RecuperarAcuses(solicitudAcuse);
      Result := respuestaAcuse.AcuseXML;
      respuestaAcuse.Free;
    except
      On E:Exception do
        ProcesarExcepcionDePAC(E);
    end;
  finally
    if Assigned(solicitudAcuse) then
      solicitudAcuse.Free;
  end;
end;

function TProveedorEcodex.CancelarDocumentos(const aUUIDS: TListadoUUID):
    TListadoCancelacionUUID;
var
  solicitudCancelacion: TEcodexSolicitudCancelaMultiple;
  respuestaCancelacion: TEcodexRespuestaCancelaMultiple;
  tokenDeUsuario: string;
  mensajeFalla: string;
  uuidPorCancelar, estado: String;
  I: Integer;
  arregloGuids : Array_Of_guid;
const
  // Ref: Pagina 15 de "Guia de integracion Ecodex".
  _CADENA_CANCELADO = 'Cancelado';
begin
  Assert(fwsCancelacionEcodex <> nil, 'La instancia fwsCancelacionEcodex no debio ser nula');

  if fwsTimbradoEcodex = nil then
    raise EPACNoConfiguradoException.Create
      ('No se ha configurado el PAC, favor de configurar con metodo Configurar');

  // 1. Creamos la solicitud de timbrado
  solicitudCancelacion := TEcodexSolicitudCancelaMultiple.Create;
  Result               := TDictionary<String, Boolean>.Create;

  try
    // 2. Iniciamos una nueva sesion solicitando un nuevo token
    tokenDeUsuario := fManejadorDeSesion.ObtenerNuevoTokenDeUsuario();

    // 3. Asignamos los parametros de cancelacion
    SetLength(arregloGuids, Length(aUUIDS));
    for I := 0 to Length(aUUIDS) - 1 do
    begin
      uuidPorCancelar := aUUIDS[I];
      arregloGuids[I] := uuidPorCancelar;
    end;

    solicitudCancelacion.TEcodexListaCancelar := TEcodexListaCancelar2.Create;
    solicitudCancelacion.TEcodexListaCancelar.guid := arregloGuids;
    solicitudCancelacion.RFC := TXSString.Create;
    solicitudCancelacion.RFC.XSToNative(fCredencialesPAC.RFC);

    solicitudCancelacion.Token := TXSString.Create;
    solicitudCancelacion.Token.XSToNative(tokenDeUsuario);

    solicitudCancelacion.TransaccionID             := fManejadorDeSesion.NumeroDeTransaccion;

    try
      mensajeFalla := '';

      // 4. Realizamos la solicitud de cancelacion
      respuestaCancelacion := fwsCancelacionEcodex.CancelaMultiple(solicitudCancelacion);

      // Convertir el array que regresa Ecodex al dictionary que
      // estamos regresando
      for I := 0 to Length(respuestaCancelacion.Resultado.TEcodexResultadoCancelacion) - 1 do
      begin
        estado := respuestaCancelacion.Resultado.TEcodexResultadoCancelacion[I].Estatus.NativeToXS;
        Result.Add(respuestaCancelacion.Resultado.TEcodexResultadoCancelacion[I].UUID,
                   estado = _CADENA_CANCELADO);
      end;


      respuestaCancelacion.Free;
    except
      On E: Exception do
        ProcesarExcepcionDePAC(E);
    end;
  finally
    if Assigned(solicitudCancelacion) then
      solicitudCancelacion.Free;
  end;
end;

end.
