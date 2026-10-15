// Tests the CloudFront Function in router.js.tftpl with Node's built-in runner:
//   node --test tests/router.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const template = readFileSync(new URL('../router.js.tftpl', import.meta.url), 'utf8');

function router(config) {
  const code = template.replace('${config}', JSON.stringify({ www: true, spa: false, redirects: {}, ...config }));
  return new Function(code + '\nreturn handler;')();
}

function request(uri, { host = 'example.com', querystring = {} } = {}) {
  return { request: { uri, querystring, headers: { host: { value: host } } } };
}

test('www redirects to the bare domain, keeping path and query', () => {
  const handler = router({ domain: 'example.com' });
  const res = handler(request('/pricing/', {
    host: 'www.example.com',
    querystring: { utm_source: { value: 'x' }, flag: { value: '' } },
  }));
  assert.equal(res.statusCode, 301);
  assert.equal(res.headers.location.value, 'https://example.com/pricing/?utm_source=x&flag');
});

test('www is left alone when include_www is off', () => {
  const handler = router({ domain: 'example.com', www: false });
  const res = handler(request('/', { host: 'www.example.com' }));
  assert.equal(res.uri, '/index.html');
});

test('directory URLs get index.html', () => {
  const handler = router({ domain: 'example.com' });
  assert.equal(handler(request('/')).uri, '/index.html');
  assert.equal(handler(request('/about/')).uri, '/about/index.html');
  assert.equal(handler(request('/about')).uri, '/about/index.html');
});

test('files pass through untouched', () => {
  const handler = router({ domain: 'example.com' });
  assert.equal(handler(request('/style.css')).uri, '/style.css');
  assert.equal(handler(request('/contact.html')).uri, '/contact.html');
});

test('SPA mode sends routes to /index.html but not files', () => {
  const handler = router({ domain: 'example.com', spa: true });
  assert.equal(handler(request('/dashboard/settings')).uri, '/index.html');
  assert.equal(handler(request('/')).uri, '/index.html');
  assert.equal(handler(request('/assets/index-abc123.js')).uri, '/assets/index-abc123.js');
});

test('redirects: relative and absolute targets, with or without a trailing slash', () => {
  const handler = router({
    domain: 'example.com',
    redirects: { '/about-us.html': '/about/', '/old-blog': 'https://blog.example.org/' },
  });
  assert.equal(handler(request('/about-us.html')).headers.location.value, 'https://example.com/about/');
  assert.equal(handler(request('/old-blog')).headers.location.value, 'https://blog.example.org/');
  assert.equal(handler(request('/old-blog/')).headers.location.value, 'https://blog.example.org/');
});
