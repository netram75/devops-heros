# Multi-stage on purpose: javac only exists in the JDK, but running the
# compiled class only needs the JRE. Shipping the JDK would drag a compiler
# and its tooling into production for no reason.

# ---- stage 1: compile ----
FROM eclipse-temurin:21-jdk AS builder
WORKDIR /build
COPY HelloWorldServer.java .
RUN javac HelloWorldServer.java

# ---- stage 2: run ----
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=builder /build/HelloWorldServer.class ./

EXPOSE 8000
CMD ["java", "HelloWorldServer"]
