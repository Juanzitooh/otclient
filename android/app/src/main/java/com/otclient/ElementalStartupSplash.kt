package com.otclient

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import com.github.otclient.R

class ElementalStartupSplash(context: Context) : FrameLayout(context) {
    private val logoMask = FrameLayout(context)
    private val logoReveal: ValueAnimator

    init {
        isClickable = true
        isFocusable = true
        setBackgroundColor(Color.rgb(8, 10, 16))

        val screenWidth = resources.displayMetrics.widthPixels
        val screenHeight = resources.displayMetrics.heightPixels
        val logoHeight = (screenHeight * 0.155f).toInt()
        val logoWidth = (logoHeight * 3.304f).toInt()
        val logoLeft = (screenWidth * 0.043f).toInt()
        val logoTop = (screenHeight * 0.045f).toInt()

        addView(
            ImageView(context).apply {
                setImageResource(R.drawable.elemental_startup_world)
                scaleType = ImageView.ScaleType.CENTER_CROP
                contentDescription = null
            },
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )
        addView(
            View(context).apply { setBackgroundColor(Color.argb(102, 8, 10, 16)) },
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )

        logoMask.clipChildren = true
        logoMask.clipToPadding = true
        addView(
            logoMask,
            LayoutParams(0, logoHeight, Gravity.TOP or Gravity.LEFT).apply {
                leftMargin = logoLeft
                topMargin = logoTop
            },
        )
        logoMask.addView(
            ImageView(context).apply {
                setImageResource(R.drawable.elemental_startup_signature)
                scaleType = ImageView.ScaleType.FIT_CENTER
                contentDescription = null
            },
            LayoutParams(logoWidth, logoHeight),
        )

        val slogan = TextView(context).apply {
            text = "COLETE, CONSTRUA, LUTE E VIVA ESSA AVENTURA"
            setTextSize(TypedValue.COMPLEX_UNIT_PX, screenHeight * 0.014f)
            setTextColor(Color.rgb(247, 241, 230))
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
            includeFontPadding = false
            maxLines = 1
            alpha = 0f
        }
        addView(
            slogan,
            LayoutParams(
                (logoWidth * 0.64f).toInt(),
                LayoutParams.WRAP_CONTENT,
                Gravity.TOP or Gravity.LEFT,
            ).apply {
                leftMargin = logoLeft + (logoWidth * 0.36f).toInt()
                topMargin = logoTop + (logoHeight * 0.73f).toInt()
            },
        )

        addStartupFooter(screenWidth, screenHeight)

        logoReveal = ValueAnimator.ofInt(0, logoWidth).apply {
            duration = 1700
            interpolator = LinearInterpolator()
            addUpdateListener { animation ->
                val params = logoMask.layoutParams as LayoutParams
                params.width = animation.animatedValue as Int
                logoMask.layoutParams = params
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    slogan.animate().alpha(1f).setDuration(360).start()
                }
            })
            start()
        }
    }

    fun release() {
        logoReveal.cancel()
    }

    private fun addStartupFooter(screenWidth: Int, screenHeight: Int) {
        val footerHeight = (screenHeight * 0.14f).toInt()
        val footer = FrameLayout(context).apply {
            setBackgroundColor(Color.argb(232, 8, 10, 16))
        }
        addView(
            footer,
            LayoutParams(LayoutParams.MATCH_PARENT, footerHeight, Gravity.BOTTOM),
        )
        footer.addView(
            View(context).apply { setBackgroundColor(Color.rgb(255, 189, 107)) },
            LayoutParams(LayoutParams.MATCH_PARENT, 1),
        )

        val leftInset = (screenWidth * 0.043f).toInt()
        val label = TextView(context).apply {
            text = "Preparando o Elemental"
            setTextSize(TypedValue.COMPLEX_UNIT_PX, screenHeight * 0.013f)
            setTextColor(Color.rgb(247, 241, 230))
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
            includeFontPadding = false
        }
        footer.addView(
            label,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                leftMargin = leftInset
                rightMargin = leftInset
                topMargin = (screenHeight * 0.035f).toInt()
            },
        )
        val detail = TextView(context).apply {
            text = "Carregando o cliente..."
            setTextSize(TypedValue.COMPLEX_UNIT_PX, screenHeight * 0.010f)
            setTextColor(Color.rgb(185, 190, 202))
            includeFontPadding = false
        }
        footer.addView(
            detail,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                leftMargin = leftInset
                rightMargin = leftInset
                topMargin = (screenHeight * 0.061f).toInt()
            },
        )
    }
}
