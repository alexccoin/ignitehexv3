# IgniteHeX v3 — the host-independent option.
#
# Serves the same static bundle Netlify would, with the same SPA fallback, so
# switching between the two changes nothing the app can observe.
#
# THE ONE THING TO UNDERSTAND BEFORE USING THIS: Vite inlines VITE_* variables
# into the JavaScript at BUILD time. They are therefore build arguments, not
# runtime environment. Setting them with `docker run -e` does nothing — the
# bundle was already written. An image is bound to one backend for its whole
# life, which is why the tag should say which:
#
#   docker build \
#     --build-arg VITE_SUPABASE_URL=https://<project>.supabase.co \
#     --build-arg VITE_SUPABASE_PUBLISHABLE_KEY=<publishable key> \
#     -t ignitehex-v3:hosted .
#
#   docker run --rm -p 8080:8080 ignitehex-v3:hosted
#
# The publishable (anon) key is designed to ship to browsers, so baking it in
# leaks nothing that the served JavaScript would not. A service-role key must
# NEVER be passed here; nothing in this image needs one.

# ------------------------------------------------------------------ build
FROM node:22-alpine AS build
WORKDIR /app

# Dependencies first, so a source-only change does not re-install.
COPY package.json package-lock.json* ./
# npm ci when there is a lockfile, npm install when there is not. The repo has
# no lockfile committed today (see docs/DEPLOYMENT.md — it is on the list of
# things that are not production-ready), and a build that silently resolves
# different dependency versions than CI did is exactly the failure a lockfile
# prevents.
RUN if [ -f package-lock.json ]; then npm ci; else npm install --no-audit --no-fund; fi

COPY . .

ARG VITE_SUPABASE_URL
ARG VITE_SUPABASE_PUBLISHABLE_KEY
ENV VITE_SUPABASE_URL=$VITE_SUPABASE_URL
ENV VITE_SUPABASE_PUBLISHABLE_KEY=$VITE_SUPABASE_PUBLISHABLE_KEY

# Fail here rather than in someone's browser. src/lib/supabase.ts throws on a
# missing variable by design; without this check that throw happens at runtime,
# after the image has been built, pushed and deployed.
RUN test -n "$VITE_SUPABASE_URL" || (echo "build-arg VITE_SUPABASE_URL is required" >&2; exit 1) && \
    test -n "$VITE_SUPABASE_PUBLISHABLE_KEY" || (echo "build-arg VITE_SUPABASE_PUBLISHABLE_KEY is required" >&2; exit 1)

RUN npm run build

# ------------------------------------------------------------------ serve
FROM nginx:1.27-alpine AS serve

COPY --from=build /app/dist /usr/share/nginx/html
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
# Outside conf.d/ on purpose: conf.d/*.conf is auto-included at http level, and
# this file is meant to be included per-location, not once globally.
COPY deploy/security-headers.conf /etc/nginx/security-headers.conf

# Port 8080 and writable paths, so the container can run as a non-root user —
# Cloud Run, Fly, ECS and most Kubernetes policies refuse root or refuse a
# privileged port, and an image that only works as root is not portable.
#
# The pid line is rewritten by matching the DIRECTIVE, not a path: this image
# says `pid /run/nginx.pid;` and older ones said `/var/run/nginx.pid`. Pinning
# the old literal is how the first version of this file passed `docker build`
# and then died on `docker run` with
#   [emerg] open() "/run/nginx.pid" failed (13: Permission denied)
# — which is the whole reason this Dockerfile is verified by serving a page
# rather than by building.
#
# 10-listen-on-ipv6-by-default.sh is removed because it rewrites
# conf.d/default.conf at boot, which a non-root user cannot do; the IPv6 listen
# it wanted to add is written into deploy/nginx.conf directly instead.
RUN sed -i 's,^\s*pid\s\+.*;,pid /tmp/nginx.pid;,' /etc/nginx/nginx.conf && \
    sed -i '/^user /d' /etc/nginx/nginx.conf && \
    rm -f /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh && \
    chown -R nginx:nginx /usr/share/nginx/html /var/cache/nginx && \
    mkdir -p /tmp/nginx && chown -R nginx:nginx /tmp/nginx && \
    grep -q 'pid /tmp/nginx.pid;' /etc/nginx/nginx.conf

USER nginx
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
