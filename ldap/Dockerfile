FROM alpine:3.22

RUN apk add --no-cache \
    bash \
    openldap \
    openldap-clients \
    openldap-back-mdb

RUN mkdir -p /etc/openldap/slapd.d /var/lib/ldap /run/openldap

COPY ldap/slapd.conf.template /etc/openldap/slapd.conf.template
COPY ldap/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 389

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
