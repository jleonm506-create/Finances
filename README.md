# Sobres

Presupuesto por quincena en sobres, registro rápido de gastos y proyecciones. La app vive en GitHub Pages; los datos, en tu proyecto de Supabase. Funciona sin internet y sincroniza cuando vuelve la conexión.

Son tres bloques, en este orden: **Supabase → GitHub → teléfono**. Unos 20 minutos la primera vez.

---

## 1. Supabase (donde viven los datos) — ✅ ya hecho

Tabla creada, RLS activo, confirmación de correo desactivada y `config.js` ya trae la URL y la key. Podés saltar al bloque 2.

<details><summary>Pasos originales, por si creás otro proyecto</summary>

1. Entrá a **supabase.com** y creá una cuenta (podés usar tu cuenta de GitHub).
2. **New project**. Ponele nombre `sobres`, inventá una contraseña de base de datos (guardala, aunque la app no la usa) y elegí la región más cercana (*East US* va bien desde Costa Rica). Tarda un minuto en crearse.
3. En el menú de la izquierda, **SQL Editor → New query**. Abrí el archivo `supabase.sql` de esta carpeta, copiá todo su contenido, pegalo ahí y tocá **Run**. Debe decir *Success*.
4. En el menú de la izquierda, **Authentication → Providers → Email**. Desactivá **Confirm email** y guardá. (Si lo dejás activo también funciona, pero vas a tener que confirmar tu correo una vez.)
5. Ahora los dos datos que la app necesita. Menú de la izquierda, **Project Settings** (el engranaje) **→ API**. Vas a ver:
   - **Project URL** — algo como `https://abcdefgh.supabase.co`
   - **anon public** key — un texto largo que empieza con `eyJ…`

   Abrí el archivo `config.js` de esta carpeta con cualquier editor de texto y reemplazá los dos valores. Queda así:

   ```js
   window.SOBRES_CONFIG = {
     url: 'https://abcdefgh.supabase.co',
     anonKey: 'eyJhbGciOi…',
   };
   ```

   La anon key es pública por diseño; lo que protege tus datos es la regla RLS que creaste en el paso 3.

</details>

---

## 2. GitHub (donde vive la app)

1. Entrá a **github.com** con tu cuenta. Arriba a la derecha, **+ → New repository**.
2. Nombre: `sobres`. Dejalo **Public** (GitHub Pages gratis lo requiere). Marcá **Add a README file**. **Create repository**.
3. En la página del repo, botón **Add file → Upload files**. Arrastrá o seleccioná **todo el contenido de esta carpeta** (`index.html`, `config.js`, `manifest.json`, `sw.js`, `supabase.sql`, la carpeta `icons`). Abajo, **Commit changes**.
4. En el repo, pestaña **Settings** (arriba) → en el menú de la izquierda, **Pages**.
5. En *Build and deployment* → *Source*: **Deploy from a branch**. *Branch*: **main**, carpeta **/ (root)**. **Save**.
6. Esperá un minuto y recargá esa misma página. Arriba va a aparecer: *Your site is live at* `https://TU-USUARIO.github.io/sobres/`. Esa es la dirección de tu app.

---

## 3. Teléfono

1. Abrí esa dirección en Chrome del teléfono.
2. Te pide correo y contraseña. La primera vez, escribilos y tocá **Crear cuenta**. Después de eso, **Entrar**.
3. En la bolsa (pestaña Reparto), abajo, debe decir **"Sincronizado con la nube ✓"**.
4. Tocá **Instalar app** en la bolsa, o menú de Chrome ⋮ → *Agregar a pantalla de inicio*.

Desde ahí abrís desde el ícono. En la PC entrás a la misma dirección con el mismo correo y ves lo mismo.

---

## Cómo funciona el guardado

- Cada cambio se guarda **primero en el dispositivo** y luego se sube a Supabase.
- Sin internet, la app sigue funcionando; el estado abajo dice *"pendiente de subir"* y sube solo cuando vuelve la conexión.
- Si abrís en dos dispositivos, gana el que guardó más recientemente. No hay mezcla de cambios — es un solo usuario.
- **Descargar respaldo** sigue existiendo por si querés una copia en un archivo, pero ya no es necesario para no perder datos.

## Actualizar la app

Cuando cambiés `index.html`: subilo al repo con **Add file → Upload files** (reemplaza el anterior) **y cambiá la versión en `sw.js`** (`sobres-v2` → `sobres-v3`). Sin ese cambio el teléfono puede seguir mostrando la versión vieja un par de aperturas.

## Archivos

| Archivo | Qué es |
|---|---|
| `index.html` | Toda la app |
| `config.js` | URL y anon key de tu Supabase — **el único que editás** |
| `supabase.sql` | La tabla y la regla de seguridad, se corre una vez |
| `manifest.json`, `sw.js`, `icons/` | Lo que la hace instalable y offline |
| `schema-relacional-futuro.sql` | Esquema normalizado, por si algún día querés reportes SQL o más usuarios. No se usa hoy. |
