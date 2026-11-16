import Foundation

// Everyday foods with typical US servings (rounded, USDA-style values). Columns:
// picture | name | other names (;) | serving | grams | kcal | protein | carbs | fat | fiber | sugar | sodium mg | vision words (;)
extension FoodCatalog {
    static let raw = """
🥚|Egg, large|eggs;boiled egg;hard boiled egg;fried egg|1 egg|50|72|6.3|0.4|4.8|0|0.2|71|egg
🍳|Scrambled eggs|scrambled;eggs scrambled|2 eggs|120|200|13|2|15|0|1.5|340|scrambled egg;omelet
🍳|Omelette, cheese|omelet|3-egg omelette|180|330|21|2|26|0|1|520|omelet;omelette
🥓|Bacon|bacon strips|3 slices|24|130|9|0.4|10|0|0|560|bacon
🌭|Breakfast sausage|sausage links;sausage patty|2 links|48|170|9|1|14|0|0.5|400|sausage
🥞|Pancakes|pancake;hotcakes|3 pancakes|150|340|9|56|9|2|12|660|pancake;pancakes
🧇|Waffle|waffles;eggo|2 waffles|70|200|5|30|7|1|4|420|waffle
🥣|Oatmeal|oats;porridge;rolled oats|1 cup cooked|234|160|6|28|3|4|1|10|oatmeal;porridge
🥣|Overnight oats|oats overnight|1 jar|250|330|14|48|9|7|14|90|oatmeal
🥣|Granola|muesli|½ cup|60|280|6|36|12|4|12|20|granola
🥣|Cereal with milk|cereal;cheerios;corn flakes;bran flakes|1 bowl|270|250|9|42|5|3|14|260|cereal
🥛|Greek yogurt, plain|greek yoghurt;fage;chobani;yogurt|¾ cup|170|100|17|6|0.7|0|6|60|yogurt
🥛|Yogurt, flavored|fruit yogurt;yoghurt|1 cup|170|150|6|26|2|0|22|80|yogurt
🥛|Cottage cheese|cottage|½ cup|113|100|12|4|4|0|4|380|cottage cheese
🥛|Milk, 2%|milk;whole milk;skim milk|1 cup|244|122|8|12|5|0|12|115|milk
🥛|Oat milk|oatly|1 cup|240|120|3|16|5|2|7|100|milk
🥛|Almond milk, unsweetened|almond milk|1 cup|240|35|1|1|3|0|0|170|milk
🍞|Toast, whole wheat|whole wheat bread;wheat toast;bread|1 slice|32|80|4|14|1|2|1.5|140|bread;toast
🍞|White bread|bread;white toast|1 slice|28|75|2.5|14|1|0.7|1.5|135|bread
🥯|Bagel|bagels|1 bagel|105|280|11|55|1.5|2|6|450|bagel
🥯|Bagel with cream cheese|bagel cream cheese|1 bagel|135|380|13|57|11|2|7|560|bagel
🥐|Croissant|croissants|1 croissant|57|230|5|26|12|1.5|6|270|croissant
🧁|Muffin, blueberry|muffin|1 muffin|113|420|6|58|18|1.5|30|380|muffin;cupcake
🍩|Donut, glazed|doughnut|1 donut|60|240|3|31|12|1|13|200|donut;doughnut
🥑|Avocado toast|avo toast|1 slice|110|240|6|22|15|7|2|300|avocado;toast
🥑|Avocado|avocados;guacamole|½ avocado|100|160|2|9|15|7|0.7|7|avocado
🍌|Banana|bananas|1 medium|118|105|1.3|27|0.4|3|14|1|banana
🍎|Apple|apples|1 medium|182|95|0.5|25|0.3|4.4|19|2|apple;granny smith
🍊|Orange|oranges;clementine;mandarin|1 medium|131|62|1.2|15|0.2|3|12|0|orange;citrus
🍓|Strawberries|strawberry|1 cup|152|50|1|12|0.5|3|7|2|strawberry
🫐|Blueberries|blueberry|1 cup|148|85|1|21|0.5|3.6|15|1|blueberry
🍇|Grapes|grape|1 cup|151|105|1|27|0.2|1.4|23|3|grape
🍉|Watermelon|melon|2 cups|300|90|2|23|0.5|1|18|3|watermelon
🍍|Pineapple|pineapple chunks|1 cup|165|82|1|22|0.2|2.3|16|2|pineapple
🥭|Mango|mangoes|1 cup|165|100|1.4|25|0.6|2.6|23|2|mango
🍑|Peach|peaches;nectarine|1 medium|150|60|1.4|15|0.4|2.3|13|0|peach
🍐|Pear|pears|1 medium|178|100|0.6|27|0.2|5.5|17|2|pear
🍒|Cherries|cherry|1 cup|138|87|1.5|22|0.3|3|18|0|cherry
🥝|Kiwi|kiwifruit|2 kiwis|150|90|1.7|22|0.8|4.5|13|4|kiwi
🍋|Lemon water|lemon|1 glass|250|6|0.1|2|0|0.1|0.5|2|lemon
🥗|Garden salad|side salad;salad;green salad|1 bowl|150|40|2|7|0.5|2.5|3|40|salad
🥗|Caesar salad|caesar|1 bowl|250|360|10|14|30|3|3|780|caesar salad
🥗|Chicken salad bowl|grilled chicken salad;chicken salad|1 bowl|350|430|38|18|23|6|7|820|salad
🥗|Cobb salad|cobb|1 bowl|380|560|36|12|42|5|5|1150|salad
🥬|Spinach|baby spinach|2 cups raw|60|14|1.7|2|0.2|1.3|0.3|47|spinach;leaf vegetable
🥦|Broccoli|broccoli florets|1 cup|91|31|2.5|6|0.3|2.4|1.5|30|broccoli
🥕|Carrots|baby carrots;carrot|1 cup|128|52|1.2|12|0.3|3.6|6|88|carrot
🥒|Cucumber|cucumbers|1 cup|120|18|0.8|4|0.1|0.6|2|2|cucumber
🍅|Tomato|tomatoes;cherry tomatoes|1 medium|123|22|1|5|0.2|1.5|3|6|tomato
🌽|Corn|sweet corn;corn on the cob|1 ear|100|90|3|19|1.4|2|6|15|corn
🫑|Bell pepper|peppers;red pepper|1 medium|120|30|1|7|0.3|2.5|5|5|bell pepper;pepper
🥔|Baked potato|potato|1 medium|173|160|4.3|37|0.2|3.8|2|17|potato;baked potato
🍠|Sweet potato|yam|1 medium|130|112|2|26|0.1|4|5.4|72|sweet potato
🍟|French fries|fries;chips (uk)|medium|117|365|4|48|17|4.4|0.3|250|french fries;fries
🍟|Hash browns|hashbrowns|1 cup|156|330|3|35|20|3|0.3|510|hash brown
🍚|White rice|rice;steamed rice|1 cup cooked|158|205|4.3|45|0.4|0.6|0|2|rice
🍚|Brown rice|brown rice|1 cup cooked|195|215|5|45|1.8|3.5|0.7|10|rice
🍚|Fried rice|chicken fried rice|1 cup|200|330|9|45|12|2|2|720|fried rice
🌾|Quinoa|quinoa|1 cup cooked|185|222|8|39|3.6|5|1.6|13|quinoa
🍝|Spaghetti with marinara|pasta;spaghetti;marinara|1½ cups|350|420|14|78|6|6|12|720|spaghetti;pasta
🍝|Spaghetti and meatballs|meatballs|1 plate|400|640|30|72|24|6|12|1150|spaghetti;meatball
🍝|Fettuccine Alfredo|alfredo|1½ cups|300|780|22|70|46|3|3|1100|pasta;carbonara
🍝|Mac and cheese|macaroni;mac n cheese|1 cup|200|380|15|44|16|2|6|820|macaroni;mac and cheese
🍜|Ramen|ramen noodles;noodle soup|1 bowl|500|560|22|70|20|3|5|2200|ramen;noodle
🍜|Pho|pho bo|1 bowl|650|450|30|60|8|2|5|1800|pho;noodle soup
🍲|Chili|chili con carne|1 cup|253|290|20|25|12|8|6|1000|chili
🍲|Chicken noodle soup|soup|1 bowl|300|120|8|15|3|1|1.5|1100|soup
🍲|Lentil soup|dal;daal|1 bowl|300|230|14|36|3|11|4|700|soup;lentil
🍛|Chicken curry|curry;tikka masala;butter chicken|1 cup|240|380|28|12|24|2|6|900|curry
🍛|Curry with rice|chicken curry and rice|1 plate|450|650|34|70|25|3|7|1100|curry;rice
🍗|Grilled chicken breast|chicken breast;chicken|1 breast (6 oz)|170|280|53|0|6|0|0|125|chicken;poultry
🍗|Chicken thigh|chicken thighs|2 thighs|180|380|42|0|23|0|0|170|chicken
🍗|Fried chicken|chicken wings;drumstick|2 pieces|200|560|40|18|36|1|0|1200|fried chicken;chicken wing
🍗|Chicken wings|wings;buffalo wings|6 wings|190|510|46|2|34|0|1|1500|chicken wing
🍗|Rotisserie chicken|chicken|1 cup|140|260|36|0|12|0|0|560|chicken
🥩|Steak|sirloin;ribeye;beef steak|6 oz|170|420|46|0|26|0|0|100|steak;beef
🍔|Hamburger|burger;cheeseburger|1 burger|220|540|30|40|29|2|8|1000|hamburger;cheeseburger;burger
🍔|Turkey burger|turkey patty|1 burger|200|420|28|32|19|2|6|780|hamburger
🌭|Hot dog|hotdog;frankfurter|1 hot dog|98|290|11|23|17|1|4|810|hot dog
🥪|Turkey sandwich|sandwich;sub;deli sandwich|1 sandwich|230|400|25|40|14|3|6|1300|sandwich;submarine sandwich
🥪|Ham and cheese sandwich|ham sandwich|1 sandwich|200|430|22|36|21|2|5|1450|sandwich
🥪|Grilled cheese|grilled cheese sandwich|1 sandwich|130|440|15|32|28|1.5|4|980|sandwich;grilled cheese
🥪|Peanut butter and jelly|pb&j;pbj|1 sandwich|100|380|12|46|17|4|20|430|sandwich
🥪|BLT|blt sandwich|1 sandwich|160|440|16|30|28|2|4|1100|sandwich
🌯|Burrito|chicken burrito;beef burrito|1 burrito|400|750|36|85|28|10|5|1700|burrito
🌯|Burrito bowl|chipotle bowl|1 bowl|500|650|42|65|24|12|5|1500|burrito;rice
🌮|Tacos|taco;beef tacos;chicken tacos|2 tacos|200|420|22|30|22|4|3|780|taco
🌯|Wrap, chicken|chicken wrap|1 wrap|250|480|30|42|20|3|4|1200|wrap;burrito
🫓|Quesadilla|cheese quesadilla|1 quesadilla|180|530|24|38|30|2|2|1100|quesadilla
🥙|Gyro|gyros;shawarma;kebab|1 gyro|280|600|28|50|32|3|4|1400|gyro;kebab
🍕|Pizza, cheese|pizza|2 slices|214|570|24|71|21|4|8|1280|pizza
🍕|Pizza, pepperoni|pepperoni pizza|2 slices|220|620|26|70|26|4|8|1400|pizza
🍣|Sushi roll|sushi;california roll;maki|8 pieces|220|330|10|58|6|3|8|700|sushi
🍣|Salmon nigiri|nigiri;sashimi|4 pieces|140|240|14|36|4|0.5|6|420|sushi;sashimi
🍱|Poke bowl|poke|1 bowl|450|620|35|70|20|5|10|1200|poke;sushi
🥡|Orange chicken|chinese food;sweet and sour chicken|1 cup|190|490|21|50|23|1|20|820|chinese food
🥡|Lo mein|chow mein;noodles|1 cup|200|310|13|43|10|3|5|1100|noodle;lo mein
🥟|Dumplings|potstickers;gyoza|6 dumplings|180|380|16|40|17|2|2|900|dumpling
🍤|Shrimp|prawns;grilled shrimp|4 oz|113|120|23|1|2|0|0|500|shrimp;prawn
🐟|Salmon fillet|salmon;baked salmon|6 oz|170|350|38|0|21|0|0|100|salmon;fish
🐟|Tuna|canned tuna;tuna can|1 can|142|160|36|0|1.2|0|0|420|tuna;fish
🐟|White fish|cod;tilapia;halibut|6 oz|170|180|39|0|2|0|0|130|fish
🐟|Fish and chips|fish n chips|1 plate|350|840|32|80|43|6|1|1100|fish and chips
🫘|Black beans|beans|1 cup|172|227|15|41|1|15|0.6|2|bean;black bean
🫘|Chickpeas|garbanzo|1 cup|164|270|15|45|4|12|8|11|chickpea
🧆|Falafel|falafels|4 pieces|68|230|9|22|12|4|0|200|falafel
🥣|Hummus|houmous|¼ cup|62|160|5|9|11|4|0.3|240|hummus
🍲|Tofu stir fry|tofu;stir fry|1 plate|350|380|22|30|18|5|8|900|tofu;stir fry
🥘|Paella|paella|1 cup|250|380|20|45|12|2|2|800|paella
🥘|Lasagna|lasagne|1 piece|250|420|24|36|20|3|8|900|lasagna
🍖|Pork chop|pork|1 chop|150|280|38|0|13|0|0|90|pork chop;pork
🍖|Ribs|bbq ribs;pork ribs|4 ribs|200|600|40|12|44|0|10|900|ribs
🍖|Pulled pork sandwich|pulled pork|1 sandwich|250|560|30|50|25|2|16|1300|sandwich;pulled pork
🥓|Turkey bacon|turkey bacon|2 slices|30|70|8|1|4|0|0|340|bacon
🧀|Cheese, cheddar|cheese;cheddar|1 oz|28|115|7|0.4|9.5|0|0.1|180|cheese
🧀|String cheese|mozzarella stick|1 stick|28|80|7|1|6|0|0|200|cheese
🧀|Cheese and crackers|crackers and cheese|1 snack|60|260|9|18|17|1|1|420|cheese;cracker
🥜|Peanut butter|pb;almond butter|2 tbsp|32|190|7|7|16|2|3|140|peanut butter
🥜|Almonds|almond|1 oz (23)|28|165|6|6|14|3.5|1.2|0|almond;nut
🥜|Mixed nuts|nuts;cashews;walnuts|1 oz|28|175|5|6|15|2|1.3|90|nut;cashew;walnut
🌰|Pumpkin seeds|pepitas|1 oz|28|160|8.5|4|14|1.7|0.4|5|seed
🌰|Chia pudding|chia|1 cup|200|260|8|26|14|12|10|80|pudding
🥨|Pretzels|pretzel|1 oz|28|110|3|23|1|1|0.5|360|pretzel
🍿|Popcorn|popcorn|3 cups popped|24|95|3|19|1|3.5|0.2|190|popcorn
🥔|Potato chips|chips;crisps|1 oz|28|155|2|15|10|1|0.2|150|potato chip;chips
🌮|Tortilla chips and salsa|chips and salsa;nachos|1 serving|60|280|4|36|13|3|2|420|nacho;tortilla chip
🧀|Nachos with cheese|nachos|1 plate|250|700|20|60|42|6|3|1300|nachos
🍫|Protein bar|quest bar;rxbar;clif bar|1 bar|60|210|20|22|8|10|1|200|candy bar
🍫|Granola bar|nature valley;kind bar|1 bar|42|190|4|28|7|2|11|150|candy bar;granola
🥤|Protein shake|whey shake;protein drink|1 shake|350|200|30|8|4|1|3|250|milkshake
🥤|Smoothie|fruit smoothie|16 oz|473|280|5|62|2|5|48|60|smoothie
🍫|Dark chocolate|chocolate 70%|1 oz|28|170|2|13|12|3|7|6|chocolate
🍫|Milk chocolate bar|chocolate;candy bar|1 bar|43|230|3|25|13|1|23|35|chocolate;candy bar
🍪|Cookie, chocolate chip|cookie;cookies|2 cookies|30|150|2|20|7|0.7|10|110|cookie
🍰|Cake slice|birthday cake;chocolate cake|1 slice|110|420|4|58|20|1.5|42|380|cake
🍦|Ice cream|gelato|1 cup|132|275|4.6|31|15|1|28|105|ice cream
🍨|Frozen yogurt|froyo|1 cup|144|220|5|38|6|0|35|110|frozen yogurt;ice cream
🥧|Apple pie|pie|1 slice|125|300|2.5|42|14|2|20|250|pie
🍮|Pudding|custard|½ cup|113|130|3|23|3|0|18|190|pudding
☕|Coffee, black|coffee;americano;drip coffee|12 oz|355|5|0.4|0|0|0|0|5|coffee;espresso
☕|Latte|cafe latte;flat white|16 oz|473|190|13|19|7|0|17|170|coffee;latte;cappuccino
☕|Cappuccino|cappucino|12 oz|355|120|8|12|4.5|0|10|110|cappuccino;coffee
☕|Iced coffee with milk|iced coffee|16 oz|473|110|3|17|3|0|15|50|iced coffee;coffee
☕|Mocha|cafe mocha|16 oz|473|360|13|44|15|2|35|170|coffee
🥤|Frappuccino|frappe|16 oz|473|380|5|60|14|0|58|240|milkshake;coffee
🍵|Tea|green tea;black tea|1 cup|240|2|0|0.5|0|0|0|7|tea
🧋|Bubble tea|boba;milk tea|16 oz|473|350|2|70|8|0|50|60|bubble tea;tea
🍊|Orange juice|oj;juice|1 cup|248|110|1.7|26|0.5|0.5|21|2|juice;orange juice
🥤|Soda|coke;pepsi;sprite;soft drink|12 oz can|355|140|0|39|0|0|39|45|soft drink;soda
🥤|Diet soda|diet coke;coke zero;zero sugar soda|12 oz can|355|0|0|0|0|0|0|40|soft drink;soda
⚡|Energy drink|red bull;monster;celsius|1 can|250|110|0|28|0|0|27|105|energy drink;can
⚡|Energy drink, sugar-free|sugar free red bull;zero energy drink|1 can|250|10|0|2|0|0|0|100|energy drink
🥤|Sports drink|gatorade;powerade|20 oz|591|140|0|36|0|0|34|270|sports drink
💧|Water|sparkling water|1 glass|250|0|0|0|0|0|0|0|water
🍺|Beer|lager;ipa|12 oz|355|155|1.6|13|0|0|0|14|beer
🍷|Wine|red wine;white wine|5 oz glass|148|125|0.1|4|0|0|1|7|wine
🍸|Cocktail|margarita;mixed drink|1 drink|200|250|0|25|0|0|22|10|cocktail
🧈|Butter|butter|1 tbsp|14|100|0.1|0|11.5|0|0|90|butter
🫒|Olive oil|oil|1 tbsp|14|120|0|0|14|0|0|0|oil
🥗|Ranch dressing|ranch;salad dressing|2 tbsp|30|130|0.4|2|13|0|1|260|dressing
🍯|Honey|honey|1 tbsp|21|64|0|17|0|0|17|1|honey
🍞|English muffin|english muffins|1 muffin|57|130|5|25|1|2|2|240|muffin;bread
🥐|Breakfast sandwich|egg mcmuffin;egg sandwich|1 sandwich|140|310|17|30|13|2|3|770|sandwich;egg
🌯|Breakfast burrito|breakfast burrito|1 burrito|250|550|24|45|30|3|3|1200|burrito
🍳|Eggs and toast|eggs toast|2 eggs + 1 toast|150|230|15|15|12|2|2|360|egg;toast
🥗|Acai bowl|acai|1 bowl|350|450|6|80|12|10|50|40|acai;smoothie bowl
🍔|Chicken sandwich|crispy chicken sandwich;chick-fil-a|1 sandwich|200|490|30|46|20|2|6|1300|sandwich;chicken
🍗|Chicken nuggets|nuggets;tenders;chicken strips|6 pieces|100|280|15|17|17|1|0|540|chicken nugget
🍝|Pasta salad|macaroni salad|1 cup|180|350|7|38|19|2|4|600|pasta;salad
🥗|Greek salad|horiatiki|1 bowl|250|250|7|12|20|3|7|780|salad;greek salad
🥗|Tuna salad|tuna mayo|½ cup|100|190|16|5|11|0|1|400|tuna;salad
🥗|Egg salad|egg mayo|½ cup|100|220|10|2|19|0|1|350|egg;salad
🍽️|Meatloaf|meat loaf|1 slice|150|330|22|12|21|0.5|5|650|meatloaf
🍽️|Roast turkey|turkey|4 oz|113|180|32|0|5|0|0|80|turkey
🥘|Pot roast|beef stew;stew|1 cup|250|340|28|20|15|3|5|800|stew
🍽️|Mashed potatoes|mash|1 cup|210|240|4|35|9|3|3|650|mashed potato
🍽️|Stuffing|dressing|½ cup|100|180|3|22|9|1.5|2|540|stuffing
🥗|Coleslaw|slaw|½ cup|95|150|1|14|10|2|10|260|coleslaw
🫛|Green beans|string beans|1 cup|125|44|2.4|10|0.4|4|2|1|green bean
🫛|Edamame|soybeans|1 cup|155|190|17|14|8|8|3.4|10|edamame
🍄|Mushrooms|sauteed mushrooms|1 cup|156|60|3.5|6|3.5|3|3|8|mushroom
🍽️|Roasted vegetables|veggies;vegetables|1 cup|150|120|3|15|6|5|7|250|vegetable
🍚|Rice and beans|beans and rice|1 cup|240|340|12|62|4|9|1|450|rice;bean
🍣|Salmon bowl|salmon rice bowl|1 bowl|450|600|38|60|20|5|6|900|salmon;rice
🍲|Miso soup|miso|1 cup|240|40|3|5|1.5|1|1|900|soup
🥪|Club sandwich|clubhouse|1 sandwich|300|590|32|42|32|3|6|1600|sandwich
🥖|Baguette|french bread|1 piece (2 oz)|57|155|5|31|1|1.3|2|330|bread;baguette
🥞|French toast|french toast|2 slices|130|360|12|40|17|1.5|10|500|french toast
🧇|Chicken and waffles|chicken waffles|1 plate|350|900|40|80|46|3|15|1800|waffle;fried chicken
🍓|Fruit cup|fruit salad|1 cup|150|80|1|20|0.3|2.5|16|5|fruit salad;fruit
🍎|Apple with peanut butter|apple pb|1 apple + 2 tbsp|214|285|7.5|32|16|6|22|142|apple
🧃|Kombucha|booch|16 oz|473|60|0|14|0|0|12|20|drink
🍽️|Bento box|bento|1 box|400|600|28|75|20|4|10|1200|bento
"""
}
