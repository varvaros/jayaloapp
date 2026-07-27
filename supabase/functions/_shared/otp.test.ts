import { assert, assertStringIncludes } from "https://deno.land/std/assert/mod.ts";
import { buildOtpMessage } from "./otp.ts";

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
