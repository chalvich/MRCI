# Inventario · trazabilidad de compras, envíos y ventas

Mini app para seguir cada pieza desde la compra en Japón hasta que se cobra la venta. Tiene catálogo con fotos, formularios para dar de alta, editar y borrar, e historial inmutable de cambios.

**Arquitectura:** GitHub Pages (la app) + Supabase (base de datos, fotos y login). Ambos tienen plan gratuito.

```
inventario-app/          ← esto va a GitHub
├── index.html           ← la app completa
├── config.js            ← aquí pegas la URL y la llave de Supabase
├── sql/01_esquema.sql   ← crea tablas, seguridad, historial y bucket de fotos
└── herramientas/migrar_excel.py

datos-privados/          ← esto NO va a GitHub (trae tus datos y los de tus clientes)
├── 02_datos_excel.sql   ← tus 36 artículos, paquetes, ventas y cargos
└── fotos_migracion/     ← las 21 fotos del Excel, nombradas por ID
```

> ⚠️ En el plan gratis de GitHub, un repo con Pages tiene que ser **público**. El código no tiene datos, así que no pasa nada. Pero **nunca subas `datos-privados/`**. Lo que protege tu información es el login y la lista de correos permitidos en Supabase.

---

## Puesta en marcha (unos 20 minutos)

### 1. Supabase
1. Crea una cuenta en <https://supabase.com> y luego **New project** (región: East US). Guarda la contraseña.
2. Abre `sql/01_esquema.sql` y, al final, **pon los correos que tendrán acceso** (el tuyo ya está; agrega el de CG).
3. En Supabase ve a **SQL Editor → New query**, pega todo `01_esquema.sql` y dale **Run**.
4. Abre otra query, pega `datos-privados/02_datos_excel.sql` y dale **Run**. Con esto se migran tus datos.
5. En **Project Settings → API**, copia la **Project URL** y la **anon / publishable key** y pégalas en `config.js`.

### 2. GitHub Pages
1. Crea un repo nuevo (por ejemplo `inventario`) y sube el contenido de `inventario-app/`.
2. Ve a **Settings → Pages → Build and deployment → Deploy from a branch → `main` / `(root)`**.
3. En 1 o 2 minutos la app queda en `https://TU-USUARIO.github.io/inventario/`.

### 3. Login
1. En Supabase ve a **Authentication → URL Configuration**:
   - **Site URL** = tu URL de GitHub Pages
   - **Redirect URLs** = agrega esa misma URL
2. **Entrar con correo**: ya funciona. Te llega un enlace mágico. El plan gratis tiene un límite bajo de correos por hora, pero la sesión dura mucho.
3. **Entrar con GitHub** (opcional, recomendado):
   - En GitHub ve a **Settings → Developer settings → OAuth Apps → New OAuth App**.
     - Homepage URL = tu URL de Pages
     - Authorization callback URL = `https://TU-PROYECTO.supabase.co/auth/v1/callback`
   - Copia el **Client ID** y genera un **Client secret**.
   - En Supabase ve a **Authentication → Sign In / Providers → GitHub**, actívalo y pega los dos valores.

### 4. Subir las fotos del Excel
Entra a la app, ve a **Catálogos → Importar fotos en lote** y selecciona todas las fotos de `datos-privados/fotos_migracion/`. Cada foto se asigna sola a su artículo porque su nombre es el ID.

---

## Cómo se usa

| Módulo | Para qué |
|---|---|
| **Tablero** | Inventario y capital invertido, utilidad esperada y realizada, lo que falta por cobrar, tarjeta pendiente, desglose por marca y últimos movimientos |
| **Inventario** | Catálogo con fotos o vista de tabla; filtros por estatus, marca y quién pagó; exportar a CSV |
| **Ficha del artículo** | Fotos (subir, usar la cámara del cel, elegir portada), costos con envío prorrateado, venta, compra, paquete, cargos y la línea de tiempo con cada cambio |
| **Paquetes** | Envíos internacionales. Si capturas el *Total MXN*, se reparte entre los artículos que no tengan envío propio |
| **Cargos TC** | Lo que se cargó a cada tarjeta, si es del negocio o personal, y el botón "Marcar pagado" |
| **Ventas** | Canal, comisión (se calcula sola según el canal), cliente, envío y depósito |
| **Historial** | Bitácora de todo: quién cambió qué y cuándo. No se puede editar ni borrar |
| **Catálogos** | Marcas, canales con su comisión y los estatus del flujo |

Flujo de estatus: **Comprado → En almacén Japón → En tránsito → Recibido/revisión → Publicado → Apartado → Vendido → Entregado**. Al registrar una venta, el artículo pasa a *Vendido* automáticamente.

---

## Cómo agregar un campo nuevo a un formulario

Ejemplo: agregar "número de serie" a los artículos.

1. En Supabase → SQL Editor:
   ```sql
   alter table articulos add column numero_serie text;
   drop view v_articulos;
   ```
   Luego vuelve a correr la sección **10 (VISTA)** de `01_esquema.sql`.
2. En `index.html`, busca `MOD = {` y, en la lista de `articulos`, agrega una línea:
   ```js
   F("numero_serie", "Número de serie"),
   ```
   Los tipos disponibles son `text`, `textarea`, `money`, `jpy`, `usd`, `number`, `date`, `select`, `list` (texto con sugerencias), `bool` y `articulo`.
3. Haz commit. GitHub Pages se actualiza solo.

---

## Pendientes que dejó la migración (revisa en la app)
- **11 artículos sin estatus** en el Excel quedaron como *Comprado*. Cámbiales el estatus desde su ficha.
- **7ff251b8 (Jimmy Choo Pumps)**: el precio USD dice 3000, pero por 25,000 ¥ deberían ser unos 165.
- **La hoja Ventas tiene 3 depósitos sin ID de artículo** (GoTrendier 6,349.60, 1,748 y una fila con solo fechas). Captúralos en la venta que corresponda.
- **Comisión de GlosetMX**: la dejé en 0 % en *Catálogos → Canales*. Pon la real. GoTrendier quedó en 18 % + $19, como en tu Excel.
- La mayoría de las ventas migradas no tienen fecha de depósito, por eso salen en "Por cobrar". Llénalas cuando confirmes el cobro.
- En las marcas, "Dior" se unió con "CHRISTIAN DIOR" y "Zimmerman" se corrigió a "ZIMMERMANN".

## Bueno saber
- Si en el plan gratis nadie usa el proyecto por una semana, Supabase lo **pausa**. Se reactiva desde el panel con un clic.
- Las fotos se comprimen antes de subir (máximo 1600 px). Con 1 GB gratis caben miles.
- Para respaldar, usa los botones **Exportar CSV** o, en Supabase, **Database → Backups**.
