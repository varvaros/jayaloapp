import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildOtpMessage, friendlyOtpError } from "./otp.ts";

Deno.test("SMS con hash cumple formato SMS Retriever", () => {
  const msg = buildOtpMessage("123456", "sms", "FA+9qCX9VSu");
  assert(msg.startsWith("<#>"), "debe iniciar con <#>");
  assertStringIncludes(msg, "123456");
  assert(msg.trimEnd().endsWith("FA+9qCX9VSu"), "el hash debe ir al final");
  assert(new TextEncoder().encode(msg).length <= 140, "≤140 bytes");
});

Deno.test("SMS sin hash usa copy normal", () => {
  const msg = buildOtpMessage("123456", "sms", null);
  assert(!msg.startsWith("<#>"));
  assertStringIncludes(msg, "123456");
});

Deno.test("WhatsApp usa copy normal aunque haya hash", () => {
  const msg = buildOtpMessage("123456", "whatsapp", "FA+9qCX9VSu");
  assert(!msg.startsWith("<#>"));
  assertStringIncludes(msg, "Jayalo");
});

// --- friendlyOtpError: el usuario NUNCA debe ver un error crudo de Twilio ---

Deno.test("numero que no recibe SMS: explica que use un celular", () => {
  const msg = friendlyOtpError(21614, "sms");
  assertStringIncludes(msg, "celular");
  assert(!msg.toLowerCase().includes("twilio"), "no debe mencionar a Twilio");
});

Deno.test("numero invalido: pide revisarlo", () => {
  assertStringIncludes(friendlyOtpError(21211, "sms"), "Rev");
});

Deno.test("pais sin permiso: lo dice claro", () => {
  assertStringIncludes(friendlyOtpError(21408, "sms"), "país");
});

Deno.test("numero que hizo STOP: explica como reactivar", () => {
  assertStringIncludes(friendlyOtpError(21610, "sms"), "START");
});

Deno.test("fallo de configuracion: no culpa al usuario", () => {
  const msg = friendlyOtpError(21606, "sms");
  assertStringIncludes(msg, "nuestro");
});

Deno.test("codigo desconocido o nulo: fallback accionable", () => {
  for (const code of [null, 99999]) {
    const msg = friendlyOtpError(code, "sms");
    assert(msg.length > 0);
    assert(!msg.toLowerCase().includes("twilio"));
    assertStringIncludes(msg, "SMS");
  }
});

Deno.test("respeta el canal en el copy", () => {
  assertStringIncludes(friendlyOtpError(30003, "whatsapp"), "WhatsApp");
  assertStringIncludes(friendlyOtpError(30003, "sms"), "SMS");
});

Deno.test("ningun mensaje filtra jerga tecnica", () => {
  const codes = [21211, 21214, 21614, 21612, 30006, 21408, 21215, 21610,
                 30003, 30005, 21617, 20003, 21606, 21266, 21212, null];
  for (const c of codes) {
    const m = friendlyOtpError(c, "sms");
    for (const jerga of ["twilio", "error [", "400", "undefined", "null"]) {
      assertEquals(m.toLowerCase().includes(jerga), false, `"${m}" filtra "${jerga}"`);
    }
  }
});
