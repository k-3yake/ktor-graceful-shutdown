FROM eclipse-temurin:21-jdk AS build

WORKDIR /app

# Maven Wrapper をコピー（プロジェクトルートから）
COPY .mvn/ .mvn/
COPY mvnw .
RUN chmod +x mvnw

# 依存関係を先にダウンロード（キャッシュ効率化）
COPY netty-with-k8s/pom.xml .
RUN ./mvnw dependency:go-offline -B

# ソースをコピーしてビルド
COPY netty-with-k8s/src/ src/
RUN ./mvnw package -DskipTests -B

FROM eclipse-temurin:21-jre

WORKDIR /app
COPY --from=build /app/target/ktor-graceful-shutdown-1.0-SNAPSHOT.jar app.jar

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]
