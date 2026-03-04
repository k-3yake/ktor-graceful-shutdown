# プロジェクト概要
Ktor 3系のグレースフルシャットダウンの動作検証プロジェクト。

## 技術スタック
- Ktor 3.3.2 / Kotlin 2.2.0 / Netty / Maven
- ビルド: `./mvnw package -DskipTests`
- 実行: `java -jar target/ktor-graceful-shutdown-1.0-SNAPSHOT.jar`
- 検証: `./verify-shutdown.sh`

## 現在の状況
TODO 1〜3は完了。TODO 4（再度検証）が残っている。

### 判明していること
- Ktor 3.0.3: `shutdownGracePeriod`/`shutdownTimeout` を application.yaml に設定すればグレースフルシャットダウンが効く
- Ktor 3.3.2: 同じ設定ではグレースフルシャットダウンが効かない（リクエストが中断される）
- この挙動の差異が検証の主題

### 次にやること
- TODO 4: Ktor 3.3.2でグレースフルシャットダウンを実現する方法を調査・実装し、再度検証

## 注意事項
- サーバー起動前に `lsof -ti:8080` でポート競合がないか確認すること
- git remote はSSH (`git@github.com:k-3yake/ktor-graceful-shutdown.git`)。HTTPSに変えないこと
