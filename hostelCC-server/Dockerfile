FROM eclipse-temurin:21-jdk AS build
WORKDIR /app
COPY .mvn .mvn
COPY mvnw pom.xml ./
RUN chmod +x mvnw && ./mvnw -B dependency:go-offline
COPY src src
RUN ./mvnw -B -DskipTests package
FROM eclipse-temurin:21-jre-alpine
RUN apk add --no-cache wget && addgroup -S hostelcc && adduser -S hostelcc -G hostelcc
WORKDIR /app
COPY --from=build /app/target/hostelcc-server-2.0.0.jar app.jar
USER hostelcc
EXPOSE 8080
ENTRYPOINT ["java","-jar","app.jar"]
