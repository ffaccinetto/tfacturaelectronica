﻿{*******************************************************}
{                                                       }
{       TFacturaElectronica                             }
{                                                       }
{       Copyright (C) 2017 Bambu Code SA de CV          }
{                                                       }
{*******************************************************}
unit Facturacion.ProveedorAutorizadoCertificacion;

interface

uses Facturacion.Comprobante,
     System.Generics.Collections,
     Facturacion.Tipos,
     System.SysUtils;

type

  TListadoUUID = Array of string;
  // NOTA: Aqui se deberá cambiar el TDictionary por otro codigo para versiones de
  // Delphi anteriores
  TListadoCancelacionUUID = TDictionary<String, Boolean>;

  EPACNoConfiguradoException = class(Exception);

  EPACException = class(ECFDIException)
  private
    fCodigoErrorSAT: Integer;
    fCodigoErrorPAC: Integer;
  public
    constructor Create(const aMensajeExcepcion: String;
                       const aCodigoErrorSAT: Integer;
                       const aCodigoErrorPAC: Integer;
                       const aReintentable: Boolean);

    property CodigoErrorSAT: Integer read fCodigoErrorSAT;
    property CodigoErrrorPAC: Integer read fCodigoErrorPAC;
  end;

  EPACServicioNoDisponibleException = class(EPACException);
  EPACCredencialesIncorrectasException = class(EPACException);
  EPACEmisorNoInscritoException = class(EPACException);
  EPACErrorGenericoDeAccesoException = class(EPACException);
  EPACTimbradoRFCNoCorrespondeException = class(EPACException);
  EPACTimbradoVersionNoSoportadaPorPACException = class(EPACException);
  EPACTimbradoSinFoliosDisponiblesException = class(EPACException);
  EPACCAnceladoSinCertificadosException = class(EPACException);
  EPACNoSePudoObtenerAcuseException = class(EPACException);
  {$REGION 'Documentation'}
  ///	<summary>
  ///	  Este tipo de excepcion se lanza cuando se detecta una falla con el
  ///	  internet del usuario el cual es un problema de comunicaci�n con el PAC.
  ///	</summary>
  {$ENDREGION}
  EPACProblemaConInternetException = class(EPACException);

  EPACProblemaTimeoutException = class(EPACException);

  {$REGION 'Documentation'}
  ///	<summary>
  ///	  Excepcion general para errores no programados/manejados.
  ///	</summary>
  ///	<remarks>
  ///	  <note type="important">
  ///	    Por defecto se establece que esta excepci�n es "re-intentable" para
  ///	    indicarle al cliente que debe de re-intentar realizar el ultimo proceso
  ///	  </note>
  ///	</remarks>
  {$ENDREGION}
  EPACErrorGenericoException = class(EPACException);


  EPACCancelacionFallidaCertificadoNoCargadoException = class(EPACErrorGenericoException);

  IProveedorAutorizadoCertificacion = interface
    ['{BB3456F4-277A-46B7-B2BC-A430E35130E8}']
    procedure Configurar(const aDominioWebService: string;
                         const aCredencialesPAC: TFacturacionCredencialesPAC;
                         const aTransaccionInicial: Int64);
    function CancelarDocumento(const aUUID: TCadenaUTF8): Boolean;
    function CancelarDocumentos(const aUUID: TListadoUUID): TListadoCancelacionUUID;
    function TimbrarDocumento(const aComprobante: IComprobanteFiscal;
                              const aTransaccion: Int64) : TCadenaUTF8;
    function ObtenerSaldoTimbresDeCliente(const aRFC: String) : Integer;
    function ObtenerAcuseDeCancelacion(const aUUID: string): string;
  end;

implementation

constructor EPACException.Create(const aMensajeExcepcion: String; const
    aCodigoErrorSAT: Integer; const aCodigoErrorPAC : Integer; const aReintentable: Boolean);
begin
  inherited Create(aMensajeExcepcion, aReintentable);
  fCodigoErrorSAT := aCodigoErrorSAT;
  fCodigoErrorPAC := aCodigoErrorPAC;
end;

end.
