from flask import Flask, jsonify

app = Flask(__name__)

@app.route("/")
def home():
    return jsonify({"status": "ok", "message": "Teya DevSecOps Demo App"})

@app.route("/health")
def health():
    return jsonify({"status": "healthy"}), 200

if __name__ == "__main__":
    # nosemgrep: python.flask.security.audit.app-run-param-config.avoid_app_run_with_bad_host
    # Development only — production uses gunicorn (see Dockerfile CMD)
    app.run(host="127.0.0.1", port=5000)
