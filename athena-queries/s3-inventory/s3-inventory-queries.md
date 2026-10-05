# S3 Inventory — Athena Queries

Base : `finops_s3` | Table : `inventory` | Workgroup : `finops-s3` (eu-west-3)

---

## Q1 — Vérification

```sql
SELECT *
FROM finops_s3.inventory
WHERE dt = '2026-06-21-01-00'
LIMIT 10;
```

---

## Q2 — Répartition par storage class (également vérifiable par Storage Lens)

```sql
SELECT storage_class,
       COUNT(*) AS nb_objets,
       ROUND(SUM(size) / 1024.0 / 1024.0, 2) AS taille_mb
FROM finops_s3.inventory
WHERE dt = '2026-06-21-01-00'
GROUP BY storage_class;
```

---

## Q3 — Objets sans lifecycle configuré

```sql
SELECT key, size, storage_class, last_modified_date
FROM finops_s3.inventory
WHERE dt = '2026-06-21-01-00'
  AND lifecycle_expiration_date IS NULL
  AND storage_class = 'STANDARD'
ORDER BY last_modified_date ASC;
```

---

## Q4 — Objets non modifiés depuis plus de 90 jours

```sql
SELECT key, size, storage_class, last_modified_date
FROM finops_s3.inventory
WHERE dt = '2026-06-21-01-00'
  AND date_diff('day', date_parse(last_modified_date, '%Y-%m-%dT%H:%i:%s.%fZ'), current_date) > 90
ORDER BY last_modified_date ASC;
```

---

## Q5 — Comparaison entre deux snapshots (objets supprimés)

```sql
SELECT a.key
FROM finops_s3.inventory a
LEFT JOIN finops_s3.inventory b
  ON a.key = b.key AND b.dt = '2026-06-21-01-00'
WHERE a.dt = '2026-06-17-01-00'
  AND b.key IS NULL;
```
