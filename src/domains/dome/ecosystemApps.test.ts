import { describe, it, expect } from 'vitest';
import { canFrame } from './ecosystemApps';

/**
 * canFrame decides whether a URL may be put in an iframe carrying
 * `sandbox="allow-scripts allow-same-origin"`.
 *
 * That pair is safe for cross-origin content and an escape hatch for
 * same-origin content: a same-origin frame with scripts can reach into the
 * parent document and read the Supabase session out of localStorage. The
 * reference implementation this was ported from created exactly that situation
 * by proxying every app through its own origin.
 *
 * So the same-origin case is not a style preference, and these tests exist so
 * that a later refactor which "simplifies" the check fails loudly.
 */
describe('canFrame', () => {
  /**
   * An https origin passed explicitly, NOT window.location.origin.
   *
   * The test environment serves over http, so every same-origin URL built from
   * the real location is already refused by the https rule — and an earlier
   * version of this file passed in full with the origin check deleted. The
   * same-origin cases must be https to reach the comparison they are testing.
   */
  const SELF = 'https://app.ignitehex.example';

  it('allows a cross-origin https URL', () => {
    expect(canFrame('https://shop.strdome.com', SELF)).toBe(true);
    expect(canFrame('https://ccoin.finance/markets?a=1', SELF)).toBe(true);
  });

  it('REFUSES a same-origin URL — this is the sandbox escape', () => {
    expect(canFrame(SELF, SELF)).toBe(false);
    expect(canFrame(`${SELF}/admin`, SELF)).toBe(false);
    expect(canFrame(`${SELF}/anything?x=1#y`, SELF)).toBe(false);
  });

  it('refuses http, which would be readable in transit inside an https page', () => {
    expect(canFrame('http://shop.strdome.com')).toBe(false);
  });

  it('refuses schemes that are not http(s) at all', () => {
    // javascript: in an iframe src executes in the embedding context.
    expect(canFrame('javascript:alert(1)')).toBe(false);
    expect(canFrame('data:text/html,<script>alert(1)</script>')).toBe(false);
    expect(canFrame('file:///etc/passwd')).toBe(false);
    expect(canFrame('about:blank')).toBe(false);
  });

  it('refuses anything unparseable rather than passing it through', () => {
    expect(canFrame('')).toBe(false);
    expect(canFrame('not a url')).toBe(false);
    expect(canFrame('//shop.strdome.com')).toBe(false);
  });

  it('compares origin, not a substring of the host', () => {
    // A host that merely CONTAINS our origin's host is still a different origin
    // and must be allowed; a check written with includes() would wrongly refuse
    // it, and — worse — the mirror-image bug would wrongly allow an attacker
    // host like "localhost.evil.com" if the comparison ran the other way.
    expect(canFrame('https://localhost.evil.com', SELF)).toBe(true);
    expect(canFrame('https://evil.com/?next=' + encodeURIComponent(SELF), SELF)).toBe(true);
  });

  it('treats a different port on the same host as cross-origin, per the origin rule', () => {
    // Same host, different port is a different origin to the browser, so
    // allow-same-origin does not grant access to this document.
    expect(canFrame('https://app.ignitehex.example:9999', SELF)).toBe(true);
  });
});
