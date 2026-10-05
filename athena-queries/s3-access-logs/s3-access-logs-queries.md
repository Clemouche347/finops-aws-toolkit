# S3 Access Logs — Athena Queries

Base : `finops_s3` | Table : `access_logs` | Workgroup : `finops-s3`

---

## Q1 — Vérification

```sql
SELECT *
FROM finops_s3.access_logs
WHERE year='2026' AND month='06' AND day='17'
LIMIT 10;
```

---

## Q2 — Répartition par opération sur une période

```sql
SELECT operation, COUNT(*) AS nb
FROM finops_s3.access_logs
WHERE year='2026' AND month='06' AND day BETWEEN '17' AND '22'
GROUP BY operation
ORDER BY nb DESC;
```

---

## Q3 — Last accessed par objet

```sql
SELECT key,
       MAX(requestdatetime) AS last_accessed
FROM finops_s3.access_logs
WHERE operation = 'REST.GET.OBJECT'
  AND year='2026' AND month='06'
GROUP BY key
ORDER BY last_accessed ASC;
```

---

## Q4 — Volume transféré par objet

```sql
SELECT key,
       COUNT(*) AS nb_acces,
       SUM(bytessent) AS bytes_total
FROM finops_s3.access_logs
WHERE operation = 'REST.GET.OBJECT'
  AND year='2026' AND month='06'
GROUP BY key
ORDER BY bytes_total DESC
LIMIT 20;
```
