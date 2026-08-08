abstract final class AppConfig {
  static const supabaseUrl = 'https://mfaiklvobnvgusbcssbx.supabase.co';
  static const supabasePublishableKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1mYWlrbHZvYm52Z3VzYmNzc2J4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI2NDQ1OTgsImV4cCI6MjA5ODIyMDU5OH0.UT_8eeSffp_K8HjykO1V9DVy81gO49-kNw1lfhQ4VcE';
  static const googleWebClientId =
      '606236193258-80p6roa1ohq3dd63n3uodnrvqncpt44k.apps.googleusercontent.com';
  static const turnstileSiteKey = '0x4AAAAAAD2eR3eQ3TC10fVF';
  static const siteUrl = 'https://jayalo.com';
  static const aiEndpoint = '$siteUrl/api/ai/chat-stream';
  static const reportErrorEndpoint = '$siteUrl/api/public/hooks/report-error';
  static const editorLinkEndpoint = '$siteUrl/api/app/business-editor-link';
  static const reverseGeocodeEndpoint = '$siteUrl/api/app/reverse-geocode';
  static const deleteAccountEndpoint = '$siteUrl/api/app/delete-account';
  static const playVerifyEndpoint = '$siteUrl/api/app/play-verify';
  static const walletUrl = '$siteUrl/provider/wallet';
  static const termsUrl = '$siteUrl/terminos';
  static const privacyUrl = '$siteUrl/privacidad';

  /// Página pública de eliminación de cuenta. Google Play exige que exista
  /// ADEMÁS del camino in-app, y hay que declararla en el formulario de
  /// Seguridad de los Datos de Play Console.
  static const deleteAccountUrl = '$siteUrl/eliminar-cuenta';

  /// DEBE coincidir con TERMS_VERSION de la web (src/components/legal).
  static const termsVersion = '2.0';
}
