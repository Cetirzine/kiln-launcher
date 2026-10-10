// 内置的微软登录 Client ID（Azure 应用注册的“应用程序（客户端）ID”）。
//
// 填写后，打包出的启动器会直接使用它，用户无需在设置中填写。
// 也可以不改这个文件，在构建时通过环境变量注入：
//     KILN_MS_CLIENT_ID=<你的 ID> ./scripts/build-app.sh
//
// 注意：新注册的 Azure 应用需要先向微软申请 Minecraft API 访问权限，否则登录会在最后一步返回 403。

package enum EmbeddedClientID {
    package static let value = "682b9eac-e9b3-4c37-a679-40c3c12627cf"
}
