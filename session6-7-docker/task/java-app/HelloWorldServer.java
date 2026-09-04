import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;

/**
 * Hello World over HTTP using the JDK's built-in HttpServer, so the container
 * needs no web framework and no build tool beyond javac.
 */
public class HelloWorldServer {

    private static final int PORT = 8000;

    private static final String PAGE = """
            <!DOCTYPE html>
            <html lang="en">
            <head>
            <meta charset="utf-8">
            <title>Hello World from Java</title>
            <style>
              body { margin:0; font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
                     display:flex; align-items:center; justify-content:center; min-height:100vh;
                     background:#450a0a; color:#fee2e2; }
              .card { text-align:center; padding:1rem; }
              h1 { font-size:1.9rem; margin:0 0 .6rem; }
              p  { margin:.2rem 0; color:#fca5a5; font-size:.95rem; }
              code { background:#7f1d1d; padding:2px 8px; border-radius:6px; color:#fecaca; }
            </style>
            </head>
            <body>
              <div class="card">
                <h1>Hello World from Java!</h1>
                <p>Served from a Docker container</p>
                <p>Built with <code>temurin:21-jdk</code>, shipped on <code>21-jre</code>, port 8000</p>
                <p>Netram, 24BCS10329</p>
              </div>
            </body>
            </html>""";

    public static void main(String[] args) throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress("0.0.0.0", PORT), 0);

        server.createContext("/", exchange -> {
            byte[] body = PAGE.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type", "text/html; charset=utf-8");
            exchange.sendResponseHeaders(200, body.length);
            try (OutputStream out = exchange.getResponseBody()) {
                out.write(body);
            }
        });

        server.setExecutor(null);
        server.start();
        System.out.println("hello-java listening on port " + PORT);
    }
}
