# kubernetes-Digital-ocean

Manifiestos de Kubernetes y un script de arranque para desplegar una aplicación de
monitoreo de sensores (temperatura, humedad y peso) de tres capas: **frontend**,
**backend** y **PostgreSQL**. Las imágenes vienen de Docker Hub (`jpcc141999/*`); este
repo no contiene código de aplicación, solo el despliegue.

> Aunque el nombre menciona DigitalOcean, los manifiestos no usan nada específico de
> ningún proveedor: funcionan en cualquier cluster (DOKS, AKS, minikube, kind, etc.)
> con `kubectl` configurado.

## Arquitectura

```
            localhost:3000                 localhost:8000
                  │  (port-forward)              │  (port-forward)
                  ▼                              ▼
   ┌──────────────────────────┐   ┌──────────────────────────┐
   │ front-service (NodePort) │   │ back-service (NodePort)  │
   │ 3000 → nodePort 32000    │   │ 8000 → nodePort 32001    │
   └────────────┬─────────────┘   └────────────┬─────────────┘
                ▼                              ▼
       front-deploy (1 réplica)      back-deployment (1 réplica)
       jpcc141999/front4             jpcc141999/back3
                                     DB_HOST=db-service
                                               │
                                               ▼
                                  db-service (ClusterIP :5432)
                                               │
                                               ▼
                                  db-deployment (1 réplica)
                                  jpcc141999/db1 (PostgreSQL)
```

| Componente | Manifiesto     | Imagen               | Puerto | Service                          |
|------------|----------------|----------------------|--------|----------------------------------|
| Base datos | `dp-db.yaml`   | `jpcc141999/db1`     | 5432   | `db-service` (ClusterIP)         |
| Backend    | `dp-back.yaml` | `jpcc141999/back3`   | 8000   | `back-service` (NodePort 32001)  |
| Frontend   | `dp-front.yaml`| `jpcc141999/front4`  | 3000   | `front-service` (NodePort 32000) |

El backend usa Alembic para las migraciones del esquema y valida contraseñas con
bcrypt (passlib).

## Estructura

```
.
├── dp-db.yaml                 # Deployment + Service de PostgreSQL
├── dp-back.yaml               # Deployment + Service del backend
├── dp-front.yaml              # Deployment + Service del frontend
├── up.sh                      # Despliegue completo + migraciones + seed + port-forward
├── sql/
│   └── seed_pablodevops.sql   # Datos de prueba (usuario, sensores, lecturas de 24 h)
└── test/                      # Manifiestos de pruebas iniciales (nginx, front1); no los usa up.sh
```

## Requisitos

- Un cluster de Kubernetes accesible y `kubectl` apuntando a él
  (`kubectl config current-context`).
- Acceso a Docker Hub para descargar las imágenes `jpcc141999/*`.

## Despliegue rápido

Desde la raíz del repo:

```bash
./up.sh
```

El script:

1. Aplica `dp-db.yaml`, `dp-back.yaml` y `dp-front.yaml` (con pausas entre cada uno).
2. Espera a que PostgreSQL acepte conexiones (`pg_isready`).
3. Corre las migraciones en el pod del backend: `alembic upgrade head`.
4. Carga los datos de prueba de `sql/seed_pablodevops.sql`.
5. Abre port-forward de ambos servicios y queda en primer plano:
   - Frontend: <http://localhost:3000>
   - Backend: <http://localhost:8000>

`Ctrl+C` detiene los port-forwards (los recursos siguen corriendo en el cluster).

## Despliegue manual

```bash
kubectl apply -f dp-db.yaml
kubectl apply -f dp-back.yaml
kubectl apply -f dp-front.yaml

# esperar a la base de datos
kubectl exec deploy/db-deployment -- pg_isready -U postgres -d postgres

# migraciones + seed
kubectl exec deploy/back-deployment -- alembic upgrade head
kubectl exec -i deploy/db-deployment -- psql -U postgres -d postgres -v ON_ERROR_STOP=1 < sql/seed_pablodevops.sql

# acceso local
kubectl port-forward svc/front-service 3000:3000
kubectl port-forward svc/back-service 8000:8000
```

Como los Services son `NodePort`, también se puede entrar por
`http://<IP-de-un-nodo>:32000` (front) y `:32001` (back) si el firewall del nodo lo
permite.

## Datos de prueba

`sql/seed_pablodevops.sql` es idempotente (se puede correr varias veces) y crea:

- Usuario `pablodevops` con rol `master` (la contraseña se guarda como hash bcrypt).
- Sensores `101`, `102`, `103`, `201` (activos) y `301` (inactivo).
- Una lectura por hora durante las últimas 24 h (zona horaria `America/Bogota`) para
  temperatura, humedad y peso.

Requiere que el esquema ya exista, es decir, correr antes `alembic upgrade head`.

## Limpieza

```bash
kubectl delete -f dp-front.yaml -f dp-back.yaml -f dp-db.yaml
```

## Limitaciones conocidas

- **Sin persistencia**: PostgreSQL corre como `Deployment` sin volumen (PVC); si el pod
  se reinicia se pierden los datos y hay que volver a correr migraciones y seed.
- **Sin alta disponibilidad**: una réplica por componente.
- **Configuración y secretos en claro**: no hay `Secret`/`ConfigMap`; las variables se
  definen directamente en los manifiestos y las credenciales de la base viven en la
  imagen `db1`.
- **Imágenes sin tag**: se usa `latest` implícito, así que un redeploy puede traer una
  versión distinta.
- **Sin probes ni límites de recursos** (`readinessProbe`, `livenessProbe`,
  `resources`), por eso `up.sh` usa `sleep` y `pg_isready` para esperar.
- Se despliega en el namespace por defecto (`default`).
