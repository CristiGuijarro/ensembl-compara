/* SQL statements that probide a summary of the data in a compara
   database. The whole lot should run within 5 mins 

  At the moment we have;
  1. Count of total number of protein trees (2 methods)
  2. Count of the total protein_members by species cf the number in trees 
  3. Breakdown of tree counts and sizes by species of the root node
*/

/* Number of Trees */
SELECT count(*) as protein_tree_count
FROM   protein_tree_node ptn
WHERE  ptn.parent_id = ptn.root_id
AND    root_id != 0;
# 1sec

/* Alternative count of Trees */
SELECT count(*) as protein_tree_count
FROM   protein_tree_node ptn, protein_tree_tag ptt
WHERE  ptn.node_id=ptt.node_id
AND    ptt.tag='gene_count';
# 2sec

/* Number of Species and their Members */
SELECT gdb.name as species_name, 
       count(*) as protein_member_count,
       sum( if( tm.member_id, 1, 0 ) ) as members_in_tree,
       round( sum( if( tm.member_id, 1, 0 ) ) * 100 
         / count(*) ) as members_in_tree_pct 
FROM   genome_db gdb, 
       member m left join protein_tree_member tm on m.member_id=tm.member_id 
WHERE  gdb.genome_db_id=m.genome_db_id 
AND    m.source_name = 'ENSEMBLPEP'
GROUP  BY gdb.name, m.source_name;
# 20sec

/* Breakdown of tree counts and sizes by species of the root node */
SELECT ptt.value as root_node_species, 
       count(*) as protein_tree_count, 
       round( avg( cast( ptt2.value as unsigned ) ) ) as avg_proteins,
       min( cast( ptt2.value as unsigned ) ) as min_proteins,
       max( cast( ptt2.value as unsigned ) ) as max_proteins
FROM   protein_tree_node ptn,
       protein_tree_tag ptt,
       protein_tree_tag ptt2
WHERE  ptn.node_id=ptt.node_id
AND    ptn.node_id=ptt2.node_id
AND    ptn.parent_id = ptn.root_id and root_id != 0
AND    ptt.tag='taxon_name'
AND    ptt2.tag='gene_count'
GROUP  BY ptt.value
ORDER  BY count(*) DESC;
# 1min
