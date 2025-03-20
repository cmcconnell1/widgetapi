# **WidgetAPI POC with AWS EKS, ALB, WAF, Cert-Manager & CI/CD**

This repository provides an **automated infrastructure setup** for deploying, testing, and validating **WidgetAPI** using:

- **Helm** for Kubernetes deployments.
- **AWS EKS** as the container platform.
- **AWS Load Balancer Controller (ALB) or NGINX Ingress** for external access.
- **AWS WAF** for security.
- **Cert-Manager** for **automatic SSL/TLS certificates**.
- **GitHub Actions for AWS CI/CD automation**.
- **Supports local testing using `kind` or `minikube`**.
- **Automated Helm testing for API functionality, including file uploads and downloads**.
- **Security scans for container vulnerabilities and Kubernetes misconfigurations**.

---

## **📂 Project Structure**
```plaintext
.
├── README.md
├── TODO.md
├── chart/                     # Helm Chart for WidgetAPI
│   ├── Chart.yaml
│   ├── values.yaml             # Default values
│   ├── local-values.yaml       # Local (kind/minikube) overrides
│   ├── dev-values.yaml         # Dev-specific overrides
│   ├── stage-values.yaml       # Stage-specific overrides
│   ├── prod-values.yaml        # Prod-specific overrides
│   ├── templates/
│   │   ├── deployment.yaml
│   │   ├── ingress.yaml
│   │   ├── networkpolicy.yaml
│   │   ├── pvc.yaml             # Persistent storage configuration
│   │   ├── secrets.yaml
│   │   ├── service.yaml
│   │   ├── cert-issuer.yaml     # Cert-Manager Let's Encrypt & Self-Signed Certificates
│   │   ├── tests/               # Helm test suite
│   │   │   ├── test-connection.yaml   # Validates service connectivity
│   │   │   ├── test-file-upload.yaml  # Verifies file upload & download API
├── iam/                        # IAM Policy Templates
│   ├── GitHubActionsPolicy.json.template
│   ├── trust-policy.json.template
├── scripts/                     # Deployment and management scripts
│   ├── attach-managed-iam-policies.sh
│   ├── create-minikube-local.sh
│   ├── delete-eks.sh
│   ├── deploy.sh
│   ├── setup-minikube-or-kind.sh   # ✅ Minikube/Kind Setup Script
│   ├── k8s-security-check.sh
│   ├── manage-eks.sh
│   ├── setup-iam-role.sh
└── secrets/                     # Processed IAM policy files
    ├── GitHubActionsPolicy.json
    ├── trust-policy.json
```

---

## **⚡ Deployment Environments**
| **Environment** | **Namespace**         | **Ingress Controller** | **Cluster Type**  |
|---------------|----------------------|----------------------|-----------------|
| **Local**     | `widgetapi-local`     | NGINX Ingress       | Minikube/Kind |
| **Dev**       | `widgetapi-dev`       | AWS ALB             | AWS EKS       |
| **Stage**     | `widgetapi-stage`     | AWS ALB             | AWS EKS       |
| **Prod**      | `widgetapi-prod`      | AWS ALB             | AWS EKS       |

---

## **🔧 Pre-requisites**
### **🔹 Local Deployment (Kind/Minikube)**
- **[Docker](https://docs.docker.com/get-docker/)**
- **[Kind](https://kind.sigs.k8s.io/docs/user/quick-start/)** or **[Minikube](https://minikube.sigs.k8s.io/docs/start/)**  
- **[Helm](https://helm.sh/docs/intro/install/)**  
- **[kubectl](https://kubernetes.io/docs/tasks/tools/)**  

#### **1️⃣ Setup Minikube or Kind**
Before deploying locally, **run the setup script** to initialize Minikube or Kind:
```sh
bash scripts/setup-minikube-or-kind.sh -m   # Use Minikube
bash scripts/setup-minikube-or-kind.sh -k   # Use Kind
```
This will:
✅ **Start Minikube/Kind**  
✅ **Enable required Minikube addons** (`ingress`, `metrics-server`, `storage-provisioner`)  
✅ **Ensure Kubernetes API is ready**  

### **🔹 AWS EKS Deployment**
- **[AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)**  
- **[eksctl](https://eksctl.io/)**  
- **[Helm](https://helm.sh/docs/intro/install/)**  
- **IAM Role for GitHub Actions (See below)**  

---

## **🔹 IAM Role for GitHub Actions**
Before deploying on AWS, you need an **IAM Role with correct permissions**.

### **1️⃣ Setup IAM Role**
```bash
bash scripts/setup-iam-role.sh
```
✅ This will:
- **Create the `GitHubActionsRole` IAM Role**  
- **Attach all required AWS permissions**  

---

## **🚀 Deployment Instructions**
### **1️⃣ Local Deployment (Kind/Minikube)**
```bash
bash scripts/deploy.sh local
```
- Installs Helm chart into the `widgetapi-local` namespace.

### **2️⃣ Deploy to AWS EKS (Dev)**
```bash
bash scripts/manage-eks.sh dev
bash scripts/deploy.sh dev
```
- Creates an EKS Cluster (`widgetapi-dev`).
- Installs Helm chart into the `widgetapi-dev` namespace.

### **3️⃣ Delete EKS Cluster**
```bash
bash scripts/delete-eks.sh dev
```
- Deletes `widgetapi-dev` EKS cluster and associated resources.

---

## **🛠 CI/CD Pipeline**
### **🔹 Automatic Deployments**
| **Branch** | **Environment** | **Namespace** | **Action** |
|------------|---------------|--------------|------------|
| `dev` | **dev** | `widgetapi-dev` | Deploys to `dev` |
| `stage` | **stage** | `widgetapi-stage` | Deploys to `stage` |
| `prod` | **prod** | `widgetapi-prod` | Deploys to `prod` |

---

## **✅ Automated Helm Tests**
Helm automatically runs **validation tests** after deployment.

### **1️⃣ Helm Chart Tests**
| **Test** | **Purpose** | **Pass Criteria** |
|----------|------------|-------------------|
| `test-connection.yaml` | Ensures service connectivity | **Receives HTTP 200** |
| `test-file-upload.yaml` | Validates file upload & retrieval | **File is correctly stored and retrieved** |

### **2️⃣ Run Helm Tests**
```bash
helm test widgetapi --namespace widgetapi-local
helm test widgetapi --namespace widgetapi-dev
helm test widgetapi --namespace widgetapi-stage
helm test widgetapi --namespace widgetapi-prod
```
✅ **Ensures WidgetAPI works correctly in each environment.**

---

## **🔒 Security Considerations**
- **❌ Do NOT hardcode credentials** in `values.yaml` (use secrets).  
- **✅ IAM Role `GitHubActionsRole` allows GitHub Actions to deploy securely.**  
- **✅ AWS Secrets Manager recommended for database credentials.**  
- **🔹 Run Kubernetes security checks before deployment:**
```bash
bash scripts/k8s-security-check.sh
```
- **Scans running containers for CVEs** using `docker scout`.
- **Verifies Helm chart security settings.**

---

## **📌 Summary**
- **Local development:** `widgetapi-local` (Minikube/Kind).  
- **Dev:** `widgetapi-dev` (AWS EKS).  
- **CI/CD:** GitHub Actions deploys automatically.  
- **Helm tests ensure deployments work.**  
- **Security best practices applied (IAM, secrets management).**  