package app.dropletmesh.id

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.util.Locale

enum class VarianteDropletId { SOMBRE, CLAIR, BLEU }

private val Encre = Color(0xFF0A1A24)
private val Bleu = Color(0xFF0A7CFF)
private val BleuClair = Color(0xFF3D9BFF)

/** Le bouton officiel « Continuer avec Droplet ID » (Jetpack Compose). */
@Composable
fun DropletIdBouton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    variante: VarianteDropletId = VarianteDropletId.SOMBRE,
    langue: String = Locale.getDefault().language,
    chargement: Boolean = false,
    pleineLargeur: Boolean = false,
) {
    val texte = if (langue == "en") "Continue with Droplet ID" else "Continuer avec Droplet ID"
    val (fond, encre, goutte) = when (variante) {
        VarianteDropletId.SOMBRE -> Triple(Encre, Color.White, BleuClair)
        VarianteDropletId.CLAIR -> Triple(Color.White, Encre, Bleu)
        VarianteDropletId.BLEU -> Triple(Bleu, Color.White, Color.White)
    }
    Surface(
        onClick = onClick,
        enabled = !chargement,
        shape = CircleShape,
        color = fond,
        border = if (variante == VarianteDropletId.CLAIR) BorderStroke(1.dp, Color(0xFFD6DEE4)) else null,
        modifier = modifier.height(48.dp).then(if (pleineLargeur) Modifier.fillMaxWidth() else Modifier).semantics { role = Role.Button },
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 20.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (chargement) {
                CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp, color = goutte)
            } else {
                Canvas(Modifier.size(18.dp)) {
                    val w = size.width
                    val h = size.height
                    val p = Path().apply {
                        moveTo(w * 0.5f, h * 0.09f)
                        cubicTo(w * 0.35f, h * 0.30f, w * 0.25f, h * 0.45f, w * 0.25f, h * 0.575f)
                        cubicTo(w * 0.25f, h * 0.85f, w * 0.75f, h * 0.85f, w * 0.75f, h * 0.575f)
                        cubicTo(w * 0.75f, h * 0.45f, w * 0.65f, h * 0.30f, w * 0.5f, h * 0.09f)
                        close()
                    }
                    drawPath(p, goutte)
                }
            }
            Spacer(Modifier.width(10.dp))
            Text(texte, color = encre, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}
